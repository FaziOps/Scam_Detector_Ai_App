from fastapi import FastAPI, APIRouter, HTTPException
from dotenv import load_dotenv
from starlette.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient
import os
import logging
import asyncio
from pathlib import Path
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
import uuid
from datetime import datetime, timedelta
import base64
import json
import re
import tempfile
import aiohttp

from google import genai
from google.genai import types as genai_types
# google-cloud-vision is optional; it requires GOOGLE_APPLICATION_CREDENTIALS
try:
    from google.cloud import vision as _vision_module
    _VISION_AVAILABLE = True
except ImportError:
    _vision_module = None
    _VISION_AVAILABLE = False

ROOT_DIR = Path(__file__).parent
load_dotenv(ROOT_DIR / '.env')

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Config / connections
# ---------------------------------------------------------------------------
mongo_url = os.environ.get('MONGO_URL', '')
db_name   = os.environ.get('DB_NAME', 'scam_detector_db')
try:
    client = AsyncIOMotorClient(mongo_url) if mongo_url else None
    db     = client[db_name] if client else None
except Exception as _mongo_err:
    logger.warning(f'MongoDB connection failed at startup: {_mongo_err}')
    client = None
    db     = None

GOOGLE_GEMINI_API_KEY = os.environ.get('GOOGLE_GEMINI_API_KEY', '') or os.environ.get('GOOGLE_API_KEY', '')
GOOGLE_API_KEY        = os.environ.get('GOOGLE_API_KEY', '')

def _is_valid_api_key(key: str) -> bool:
    """Return True only if the key looks like a real API key (not a placeholder)."""
    if not key or len(key) < 10:
        return False
    placeholders = ['your', '_here', 'placeholder', 'example', 'change_me', 'key-here', 'api_key']
    return not any(p in key.lower() for p in placeholders)

gemini_client = genai.Client(api_key=GOOGLE_GEMINI_API_KEY) if _is_valid_api_key(GOOGLE_GEMINI_API_KEY) else None

GEMINI_SYSTEM_PROMPT = (
    "You are an expert fraud detection assistant. Analyse the provided content for scam indicators.\n\n"
    "Consider:\n"
    "1. Urgency or pressure tactics\n"
    "2. Requests for sensitive information\n"
    "3. Impersonation attempts\n"
    "4. Suspicious promises or threats\n"
    "5. Grammar / formatting inconsistencies\n"
    "6. Overall scam likelihood\n\n"
    "Respond with ONLY a JSON object, no markdown fences, no other text:\n"
    '{"is_scam_likely": boolean, "confidence": float 0.0-1.0, '
    '"key_findings": ["list","of","specific","concerns"], '
    '"summary": "one or two sentence plain-language explanation"}'
)

app = FastAPI(title="Scam Detector AI API")
api_router = APIRouter(prefix="/api")

# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class TextAnalysisRequest(BaseModel):
    text: str
    device_id: str

class URLAnalysisRequest(BaseModel):
    url: str
    device_id: str

class ImageAnalysisRequest(BaseModel):
    image_base64: str
    device_id: str

class FraudIndicator(BaseModel):
    name: str
    detected: bool
    severity: str  # "low", "medium", "high", "critical"
    description: str

class AnalysisResult(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    analysis_type: str  # "text", "url", "image"
    scam_score: int  # 0-100
    risk_level: str  # "Low Risk", "Medium Risk", "High Risk", "Critical Risk"
    confidence: float  # 0.0-1.0
    indicators: List[FraudIndicator]
    recommendation: str
    summary: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    extracted_data: Optional[Dict[str, Any]] = None

class ScamReport(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    report_type: str  # "phone", "url", "pattern"
    value: str
    category: str
    description: Optional[str] = None
    status: str = "user_reported"  # "user_reported", "confirmed_scam", "rejected"
    report_count: int = 1
    device_id: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

class ScamReportCreate(BaseModel):
    report_type: str
    value: str
    category: str
    description: Optional[str] = None
    device_id: str

class DatabaseSearchRequest(BaseModel):
    query: str
    search_type: Optional[str] = "all"  # "phone", "url", "pattern", "all"

class RateLimitCheck(BaseModel):
    device_id: str
    allowed: bool
    remaining: int
    reset_at: datetime

# ---------------------------------------------------------------------------
# Fraud detection: pattern rules
# ---------------------------------------------------------------------------

URGENCY_PATTERNS = [
    r'\bact now\b', r'\burgent\b', r'\bimmediately\b', r'\blimited time\b',
    r'\bexpires\b', r'\bhurry\b', r'\btoday only\b'
]

SENSITIVE_DATA_PATTERNS = [
    r'\bpassword\b', r'\bpin\b', r'\botp\b', r'\bcvv\b', r'\bcard number\b',
    r'\bsocial security\b', r'\bssn\b', r'\bbank account\b', r'\bcredit card\b'
]

PAYMENT_REQUEST_PATTERNS = [
    r'\bgift card\b', r'\bwire transfer\b', r'\bsend money\b', r'\bpay now\b',
    r'\bfee\b', r'\bpayment required\b', r'\badvance payment\b'
]

PRIZE_SCAM_PATTERNS = [
    r"\byou.?ve won\b", r'\bcongratulations\b', r'\bprize\b', r'\blottery\b',
    r'\binheritance\b', r'\bclaim your\b', r'\bfree gift\b'
]

IMPERSONATION_PATTERNS = [
    r'\bbank\b', r'\birs\b', r'\bgovernment\b', r'\btax\b', r'\bfedex\b',
    r'\bups\b', r'\bamazon\b', r'\bpaypal\b', r'\bapple\b', r'\bmicrosoft\b'
]


def check_pattern_indicators(text: str) -> List[FraudIndicator]:
    indicators: List[FraudIndicator] = []
    text_lower = text.lower()

    if any(re.search(p, text_lower) for p in URGENCY_PATTERNS):
        indicators.append(FraudIndicator(
            name="urgency_pressure",
            detected=True,
            severity="medium",
            description="Message uses urgency or pressure tactics to force quick action"
        ))

    if any(re.search(p, text_lower) for p in SENSITIVE_DATA_PATTERNS):
        indicators.append(FraudIndicator(
            name="sensitive_data_request",
            detected=True,
            severity="critical",
            description="Message requests sensitive information like passwords or OTPs"
        ))

    if any(re.search(p, text_lower) for p in PAYMENT_REQUEST_PATTERNS):
        indicators.append(FraudIndicator(
            name="payment_request",
            detected=True,
            severity="high",
            description="Message requests upfront payment or unusual payment methods"
        ))

    if any(re.search(p, text_lower) for p in PRIZE_SCAM_PATTERNS):
        indicators.append(FraudIndicator(
            name="prize_scam",
            detected=True,
            severity="high",
            description="Message claims you've won a prize or lottery"
        ))

    if any(re.search(p, text_lower) for p in IMPERSONATION_PATTERNS):
        indicators.append(FraudIndicator(
            name="potential_impersonation",
            detected=True,
            severity="medium",
            description="Message may be impersonating a known organization"
        ))

    return indicators


def check_url_indicators(url: str) -> List[FraudIndicator]:
    indicators: List[FraudIndicator] = []
    url_lower = url.lower()

    if re.search(r'\d+\.\d+\.\d+\.\d+', url):
        indicators.append(FraudIndicator(
            name="ip_address_url",
            detected=True,
            severity="high",
            description="URL uses an IP address instead of a domain name"
        ))

    shorteners = ['bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'ow.ly']
    if any(s in url_lower for s in shorteners):
        indicators.append(FraudIndicator(
            name="url_shortener",
            detected=True,
            severity="medium",
            description="URL uses a link shortener, hiding the true destination"
        ))

    if url_lower.startswith('http://'):
        indicators.append(FraudIndicator(
            name="no_https",
            detected=True,
            severity="medium",
            description="URL does not use a secure HTTPS connection"
        ))

    suspicious_tlds = ['.tk', '.ml', '.ga', '.cf', '.zip', '.top']
    if any(url_lower.endswith(tld) for tld in suspicious_tlds):
        indicators.append(FraudIndicator(
            name="suspicious_tld",
            detected=True,
            severity="high",
            description="URL uses a domain extension commonly associated with scams"
        ))

    typosquat_patterns = ['paypa1', 'g00gle', 'faceb00k', 'arnazon', 'micros0ft']
    if any(p in url_lower for p in typosquat_patterns):
        indicators.append(FraudIndicator(
            name="typosquatting",
            detected=True,
            severity="critical",
            description="URL appears to be impersonating a legitimate website"
        ))

    return indicators


def calculate_scam_score(indicators: List[FraudIndicator]):
    if not indicators:
        return 15, "Low Risk", 0.85

    severity_weights = {"low": 10, "medium": 25, "high": 40, "critical": 60}

    total_score = 15
    for ind in indicators:
        if ind.detected:
            total_score += severity_weights.get(ind.severity, 10)

    total_score = min(total_score, 100)

    if total_score < 30:
        risk_level = "Low Risk"
    elif total_score < 60:
        risk_level = "Medium Risk"
    elif total_score < 80:
        risk_level = "High Risk"
    else:
        risk_level = "Critical Risk"

    confidence = min(0.6 + (len(indicators) * 0.08), 0.95)

    return total_score, risk_level, confidence


def generate_recommendation(score: int) -> str:
    if score >= 80:
        return "DO NOT RESPOND or click any links. This is highly likely a scam. Block and delete immediately."
    elif score >= 60:
        return "Be extremely cautious. Do not share personal information or click links. Verify through official channels."
    elif score >= 30:
        return "Exercise caution. If this is from a known organization, contact them directly using official contact information found independently (not from this message)."
    else:
        return "Low risk detected, but always verify unexpected messages through official channels before taking action."


# ---------------------------------------------------------------------------
# AI analysis via Anthropic
# ---------------------------------------------------------------------------

async def analyze_with_gemini(text: str, analysis_type: str) -> Dict[str, Any]:
    """Use Gemini for advanced text analysis. Returns a dict, never raises."""
    if not gemini_client:
        # No API key — do a thorough local pattern analysis on the actual text
        text_lower = text.lower()
        key_findings: List[str] = []
        scam_score_boost = 0

        urgency_hits = [w for w in ["urgent", "immediately", "act now", "expire", "last chance", "limited time", "today only"] if w in text_lower]
        if urgency_hits:
            key_findings.append(f"Urgency/pressure language detected: {', '.join(urgency_hits[:3])}")
            scam_score_boost += 30

        sensitive_hits = [w for w in ["otp", "pin", "password", "cvv", "card number", "bank account", "social security", "ssn", "verify your", "confirm your"] if w in text_lower]
        if sensitive_hits:
            key_findings.append(f"Requests sensitive information: {', '.join(sensitive_hits[:3])}")
            scam_score_boost += 50

        payment_hits = [w for w in ["wire transfer", "gift card", "send money", "pay now", "advance payment", "western union", "bitcoin", "crypto"] if w in text_lower]
        if payment_hits:
            key_findings.append(f"Unusual payment method requested: {', '.join(payment_hits[:3])}")
            scam_score_boost += 40

        prize_hits = [w for w in ["you've won", "you have won", "congratulations", "prize", "lottery", "inheritance", "claim your", "free gift"] if w in text_lower]
        if prize_hits:
            key_findings.append(f"Prize/lottery scam language: {', '.join(prize_hits[:3])}")
            scam_score_boost += 35

        suspend_hits = [w for w in ["suspend", "compromise", "account locked", "unusual activity", "verify immediately", "security alert"] if w in text_lower]
        if suspend_hits:
            key_findings.append(f"Account suspension/threat tactic: {', '.join(suspend_hits[:3])}")
            scam_score_boost += 35

        impersonation_hits = [w for w in ["irs", "tax authority", "police", "fbi", "microsoft support", "apple support", "amazon", "paypal", "fedex", "ups", "wells fargo", "chase bank"] if w in text_lower]
        if impersonation_hits:
            key_findings.append(f"Possible impersonation of known entity: {', '.join(impersonation_hits[:3])}")
            scam_score_boost += 20

        is_scam = scam_score_boost >= 30
        confidence = min(0.5 + (scam_score_boost / 150), 0.95) if is_scam else max(0.75 - (scam_score_boost / 100), 0.4)

        if is_scam:
            summary_parts = key_findings[:2] if key_findings else ["suspicious patterns found"]
            summary = f"Pattern analysis flagged this content: {'; '.join(summary_parts)}."
        else:
            summary = "No significant scam indicators detected in the provided content."

        return {
            "is_scam_likely": is_scam,
            "confidence": round(confidence, 2),
            "key_findings": key_findings,
            "summary": summary
        }

    prompt = f"Analyse this {analysis_type} for scam indicators:\n\n{text}"

    try:
        response = await gemini_client.aio.models.generate_content(
            model='gemini-2.0-flash-lite',
            contents=prompt,
            config=genai_types.GenerateContentConfig(
                system_instruction=GEMINI_SYSTEM_PROMPT,
                max_output_tokens=500,
                temperature=0.1,
            )
        )
        full_response = response.text.strip()

        # Strip optional markdown fences
        full_response = re.sub(r'^```(?:json)?\s*|\s*```$', '', full_response, flags=re.MULTILINE).strip()

        try:
            json_match = re.search(r'\{.*\}', full_response, re.DOTALL)
            if json_match:
                result = json.loads(json_match.group())
            else:
                result = {
                    "is_scam_likely": False,
                    "confidence": 0.5,
                    "key_findings": [],
                    "summary": full_response[:300]
                }
        except json.JSONDecodeError:
            result = {
                "is_scam_likely": False,
                "confidence": 0.5,
                "key_findings": [],
                "summary": full_response[:300]
            }

        return result

    except Exception as e:
        logger.error(f"Gemini analysis error: {e}")
        return {
            "is_scam_likely": False,
            "confidence": 0.3,
            "key_findings": [],
            "summary": f"AI analysis unavailable (service error): {e}"
        }


# ---------------------------------------------------------------------------
# Gemini Vision — image analysis (replaces Google Cloud Vision OCR)
# ---------------------------------------------------------------------------

async def perform_local_ocr(image_base64: str) -> str:
    """Perform local OCR on macOS using the compiled Swift Vision binary."""
    try:
        if ',' in image_base64:
            image_base64 = image_base64.split(',')[1]
        image_bytes = base64.b64decode(image_base64)
        
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as temp_file:
            temp_file.write(image_bytes)
            temp_path = temp_file.name
            
        try:
            # Call the compiled ocr binary
            ocr_binary = str(ROOT_DIR / 'ocr')
            proc = await asyncio.create_subprocess_exec(
                ocr_binary, temp_path,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await proc.communicate()
            if proc.returncode == 0:
                return stdout.decode('utf-8', errors='ignore').strip()
            else:
                logger.warning(f"Local OCR failed with stderr: {stderr.decode()}")
                return ""
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)
    except Exception as e:
        logger.error(f"Local OCR exception: {e}")
        return ""

async def analyze_image_with_gemini(image_base64: str) -> Dict[str, Any]:
    """Use Gemini multimodal to read text and detect scams in a screenshot. Never raises."""
    if not gemini_client:
        extracted = await perform_local_ocr(image_base64)
        if not extracted:
            # No OCR text available — return a neutral result, not a fake high-risk one
            return {
                "success": True,
                "extracted_text": "",
                "word_count": 0,
                "is_scam_likely": False,
                "confidence": 0.2,
                "key_findings": ["Could not extract text from image (add GOOGLE_GEMINI_API_KEY for full AI analysis)"],
                "summary": "No text could be extracted from this image. Add a Gemini API key for full screenshot analysis.",
                "payment_info": {}
            }

        # Thoroughly analyze the extracted OCR text for scam signals
        text_lower = extracted.lower()
        key_findings: List[str] = []
        is_scam = False

        # Check for urgency/pressure
        urgency_words = [w for w in ["urgent", "immediately", "act now", "expire", "suspended", "blocked"] if w in text_lower]
        if urgency_words:
            key_findings.append(f"Urgency language found: {', '.join(urgency_words[:3])}")
            is_scam = True

        # Check for sensitive info requests
        sensitive_words = [w for w in ["otp", "pin", "password", "cvv", "verify", "confirm your account", "bank account", "card number"] if w in text_lower]
        if sensitive_words:
            key_findings.append(f"Sensitive information requested: {', '.join(sensitive_words[:3])}")
            is_scam = True

        # Check for unusual payment methods
        payment_words = [w for w in ["gift card", "wire transfer", "bitcoin", "crypto", "western union", "send money"] if w in text_lower]
        if payment_words:
            key_findings.append(f"Unusual payment method: {', '.join(payment_words[:3])}")
            is_scam = True

        # Check for prize/lottery scams
        prize_words = [w for w in ["won", "winner", "prize", "lottery", "congratulations", "claim"] if w in text_lower]
        if prize_words:
            key_findings.append(f"Prize/lottery language: {', '.join(prize_words[:3])}")
            is_scam = True

        # Check for impersonation
        impersonation_words = [w for w in ["security alert", "amazon", "paypal", "fedex", "ups", "irs", "microsoft", "apple", "google", "chase", "wellsfargo"] if w in text_lower]
        if impersonation_words:
            key_findings.append(f"Possible impersonation: {', '.join(impersonation_words[:3])}")
            is_scam = True

        # Look for URLs in text
        urls = re.findall(r'https?://[^\s]+', extracted)
        if urls:
            key_findings.append(f"URL(s) found in image: {', '.join(urls[:2])}")
            # Only flag URLs as scam signal if combined with other indicators
            if is_scam or len(urls) > 1:
                is_scam = True

        # Check for payment receipt indicators (legitimate)
        receipt_words = [w for w in ["transaction id", "receipt", "payment successful", "paid", "upi", "ref no", "txn"] if w in text_lower]
        is_payment_receipt = len(receipt_words) > 0

        confidence = 0.75 if key_findings else 0.6
        if is_payment_receipt and not is_scam:
            summary = f"Image appears to be a legitimate payment receipt. {len(receipt_words)} receipt indicator(s) found."
        elif is_scam:
            summary = f"Suspicious content detected in screenshot: {'; '.join(key_findings[:2])}."
        else:
            summary = f"No obvious scam indicators found in the screenshot text. Content appears normal."

        # Extract payment info from the OCR text
        payment_info = {}
        amount_match = re.search(r'[\$\u20b9Rs\.]+\s*(\d+(?:[,.]\d+)*)', extracted)
        if amount_match:
            payment_info["amount"] = amount_match.group(0).strip()
        txn_match = re.search(r'(?:txn|ref|utr|transaction)[\s:]+([A-Z0-9]+)', extracted, re.IGNORECASE)
        if txn_match:
            payment_info["transaction_id"] = txn_match.group(1)

        return {
            "success": True,
            "extracted_text": extracted,
            "word_count": len(extracted.split()),
            "is_scam_likely": is_scam,
            "confidence": confidence,
            "key_findings": key_findings,
            "summary": summary,
            "payment_info": payment_info
        }

    try:
        b64 = image_base64.split(',')[-1] if ',' in image_base64 else image_base64
        image_bytes = base64.b64decode(b64)
        mime_type = 'image/png' if b64.startswith('iVBOR') else 'image/jpeg'

        prompt = (
            "Analyze this payment/transaction screenshot carefully.\n\n"
            "1. Extract ALL visible text from the image.\n"
            "2. Check if this looks like a genuine payment receipt or a fake/manipulated one.\n"
            "3. Flag suspicious elements: unusual amounts, pressure tactics, mismatched info, "
            "fake logos, or signs of editing.\n\n"
            "Respond with ONLY valid JSON (no markdown fences, no extra text):\n"
            '{"extracted_text": "all text visible in image", '
            '"is_scam_likely": boolean, '
            '"confidence": float 0.0-1.0, '
            '"key_findings": ["list","of","concerns"], '
            '"summary": "1-2 sentence plain explanation", '
            '"payment_info": {"amount": "or null", "transaction_id": "or null", '
            '"sender": "or null", "receiver": "or null"}}'
        )

        response = await gemini_client.aio.models.generate_content(
            model='gemini-2.0-flash-lite',
            contents=[
                genai_types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                prompt,
            ],
            config=genai_types.GenerateContentConfig(
                max_output_tokens=800,
                temperature=0.1,
            )
        )

        raw = response.text.strip()
        raw = re.sub(r'^```(?:json)?\s*|\s*```$', '', raw, flags=re.MULTILINE).strip()
        json_match = re.search(r'\{.*\}', raw, re.DOTALL)
        if not json_match:
            raise ValueError(f"No JSON in Gemini response: {raw[:200]}")

        result = json.loads(json_match.group())
        result['success'] = True
        extracted = result.get('extracted_text', '')
        result['word_count'] = len(extracted.split()) if extracted else 0
        return result

    except Exception as e:
        logger.error(f"Gemini vision error: {e}")
        return {
            "success": False,
            "extracted_text": "",
            "word_count": 0,
            "is_scam_likely": False,
            "confidence": 0.3,
            "key_findings": [],
            "summary": f"Image AI analysis failed: {e}",
            "payment_info": {}
        }


# ---------------------------------------------------------------------------
# Google Safe Browsing + Vision OCR (fallback)
# ---------------------------------------------------------------------------

async def check_google_safe_browsing(url: str) -> Dict[str, Any]:
    try:
        api_url = f"https://safebrowsing.googleapis.com/v4/threatMatches:find?key={GOOGLE_API_KEY}"

        payload = {
            "client": {"clientId": "scam-detector-ai", "clientVersion": "1.0.0"},
            "threatInfo": {
                "threatTypes": ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE", "POTENTIALLY_HARMFUL_APPLICATION"],
                "platformTypes": ["ANY_PLATFORM"],
                "threatEntryTypes": ["URL"],
                "threatEntries": [{"url": url}]
            }
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(api_url, json=payload, timeout=aiohttp.ClientTimeout(total=10)) as response:
                if response.status == 200:
                    data = await response.json()
                    return {
                        "is_threat": "matches" in data and len(data["matches"]) > 0,
                        "threat_types": [m["threatType"] for m in data.get("matches", [])]
                    }
                logger.warning(f"Safe Browsing API returned {response.status}")
                return {"is_threat": False, "threat_types": []}

    except Exception as e:
        logger.error(f"Google Safe Browsing error: {e}")
        return {"is_threat": False, "threat_types": []}


async def perform_ocr(image_base64: str) -> Dict[str, Any]:
    if not _VISION_AVAILABLE:
        return {"success": False, "text": "", "error": "google-cloud-vision not installed"}

    gcp_creds = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS', '')
    if not gcp_creds:
        return {"success": False, "text": "",
                "error": "GOOGLE_APPLICATION_CREDENTIALS env var not set"}

    try:
        if ',' in image_base64:
            image_base64 = image_base64.split(',')[1]

        image_bytes = base64.b64decode(image_base64)

        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as temp_file:
            temp_file.write(image_bytes)
            temp_path = temp_file.name

        try:
            vision_client = _vision_module.ImageAnnotatorClient()

            with open(temp_path, 'rb') as image_file:
                content = image_file.read()

            image = _vision_module.Image(content=content)
            response = vision_client.text_detection(image=image)
            texts = response.text_annotations

            if texts:
                extracted_text = texts[0].description
                return {"success": True, "text": extracted_text, "word_count": len(extracted_text.split())}
            return {"success": False, "text": "", "word_count": 0}

        finally:
            os.unlink(temp_path)

    except Exception as e:
        logger.error(f"OCR error: {e}")
        return {"success": False, "text": "", "error": str(e)}


def analyze_payment_screenshot(ocr_text: str) -> Dict[str, Any]:
    analysis: Dict[str, Any] = {
        "contains_payment_info": False,
        "extracted_amount": None,
        "extracted_date": None,
        "extracted_id": None,
    }

    payment_keywords = ['paid', 'payment', 'transaction', 'transfer', 'upi', 'bank', 'amount']
    if any(k in ocr_text.lower() for k in payment_keywords):
        analysis["contains_payment_info"] = True

    amount_patterns = [
        r'[\$\u20b9]\s*(\d+(?:,\d+)*(?:\.\d+)?)',
        r'(?:rs|inr|usd)\s*(\d+(?:,\d+)*(?:\.\d+)?)',
    ]
    for pattern in amount_patterns:
        match = re.search(pattern, ocr_text, re.IGNORECASE)
        if match:
            analysis["extracted_amount"] = match.group(1)
            break

    id_patterns = [
        r'(?:transaction|ref|utr|id)[\s:]*([A-Z0-9]+)',
        r'\b([0-9]{10,})\b'
    ]
    for pattern in id_patterns:
        match = re.search(pattern, ocr_text, re.IGNORECASE)
        if match:
            analysis["extracted_id"] = match.group(1)
            break

    date_match = re.search(r'\b(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\b', ocr_text)
    if date_match:
        analysis["extracted_date"] = date_match.group(1)

    return analysis


# ---------------------------------------------------------------------------
# Rate limiting
# ---------------------------------------------------------------------------

DAILY_LIMIT = 20

async def check_rate_limit(device_id: str) -> RateLimitCheck:
    if db is None:
        # No DB — allow everything
        return RateLimitCheck(device_id=device_id, allowed=True, remaining=DAILY_LIMIT,
                              reset_at=datetime.utcnow())

    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)

    count = await db.rate_limits.count_documents({
        "device_id": device_id,
        "timestamp": {"$gte": today_start}
    })

    allowed = count < DAILY_LIMIT
    remaining = max(0, DAILY_LIMIT - count)
    reset_at = today_start + timedelta(days=1)

    return RateLimitCheck(device_id=device_id, allowed=allowed, remaining=remaining, reset_at=reset_at)


async def record_usage(device_id: str):
    if db is not None:
        await db.rate_limits.insert_one({"device_id": device_id, "timestamp": datetime.utcnow()})


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@api_router.post("/analyze/text", response_model=AnalysisResult)
async def analyze_text(request: TextAnalysisRequest):
    try:
        rate_limit = await check_rate_limit(request.device_id)
        if not rate_limit.allowed:
            raise HTTPException(status_code=429, detail=f"Daily limit reached. Resets at {rate_limit.reset_at.isoformat()}")

        if len(request.text.strip()) < 5:
            raise HTTPException(status_code=400, detail="Text too short to analyze meaningfully.")

        indicators = check_pattern_indicators(request.text)

        if db is not None:
            db_matches = await db.scam_reports.find({
                "value": {"$regex": re.escape(request.text[:50]), "$options": "i"},
                "status": "confirmed_scam"
            }).to_list(5)

            if db_matches:
                indicators.append(FraudIndicator(
                    name="community_database_match",
                    detected=True,
                    severity="critical",
                    description=f"Similar message reported {len(db_matches)} time(s) as a confirmed scam"
                ))

        ai_result = await analyze_with_gemini(request.text, "text message")

        if ai_result.get("is_scam_likely"):
            indicators.append(FraudIndicator(
                name="ai_detected_scam",
                detected=True,
                severity="high",
                description=f"AI analysis: {ai_result.get('summary', 'Suspicious patterns detected')}"
            ))

        score, risk_level, confidence = calculate_scam_score(indicators)
        confidence = (confidence + ai_result.get("confidence", 0.5)) / 2

        result = AnalysisResult(
            analysis_type="text",
            scam_score=score,
            risk_level=risk_level,
            confidence=round(confidence, 2),
            indicators=indicators,
            recommendation=generate_recommendation(score),
            summary=ai_result.get("summary", f"Analyzed text message with {len(indicators)} indicator(s) detected.")
        )

        await record_usage(request.device_id)
        return result

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Text analysis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@api_router.post("/analyze/url", response_model=AnalysisResult)
async def analyze_url(request: URLAnalysisRequest):
    try:
        rate_limit = await check_rate_limit(request.device_id)
        if not rate_limit.allowed:
            raise HTTPException(status_code=429, detail=f"Daily limit reached. Resets at {rate_limit.reset_at.isoformat()}")

        if not request.url.strip():
            raise HTTPException(status_code=400, detail="URL cannot be empty.")

        indicators = check_url_indicators(request.url)

        safe_browsing_result = await check_google_safe_browsing(request.url)
        if safe_browsing_result["is_threat"]:
            indicators.append(FraudIndicator(
                name="google_safe_browsing_threat",
                detected=True,
                severity="critical",
                description=f"Google Safe Browsing flagged this URL for: {', '.join(safe_browsing_result['threat_types'])}"
            ))

        if db is not None:
            db_match = await db.scam_reports.find_one({"value": request.url, "status": "confirmed_scam"})
            if db_match:
                indicators.append(FraudIndicator(
                    name="community_database_match",
                    detected=True,
                    severity="critical",
                    description=f"URL reported as scam with {db_match.get('report_count', 1)} report(s)"
                ))

        score, risk_level, confidence = calculate_scam_score(indicators)

        result = AnalysisResult(
            analysis_type="url",
            scam_score=score,
            risk_level=risk_level,
            confidence=round(confidence, 2),
            indicators=indicators,
            recommendation=generate_recommendation(score),
            summary=f"URL analysis completed with {len(indicators)} risk indicator(s) found."
        )

        await record_usage(request.device_id)
        return result

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"URL analysis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@api_router.post("/analyze/image", response_model=AnalysisResult)
async def analyze_image(request: ImageAnalysisRequest):
    try:
        rate_limit = await check_rate_limit(request.device_id)
        if not rate_limit.allowed:
            raise HTTPException(status_code=429, detail=f"Daily limit reached. Resets at {rate_limit.reset_at.isoformat()}")

        indicators: List[FraudIndicator] = []

        # --- Primary: Gemini multimodal vision ---
        vision = await analyze_image_with_gemini(request.image_base64)

        if vision.get("success"):
            extracted_text = vision.get("extracted_text", "")
            word_count     = vision.get("word_count", 0)

            # Also run text-pattern checks on the extracted text
            if extracted_text:
                indicators.extend(check_pattern_indicators(extracted_text))
                payment_analysis = analyze_payment_screenshot(extracted_text)
            else:
                payment_analysis = {"contains_payment_info": False,
                                    "extracted_amount": None,
                                    "extracted_date": None,
                                    "extracted_id": None}

            if word_count < 5:
                indicators.append(FraudIndicator(
                    name="insufficient_text",
                    detected=True,
                    severity="medium",
                    description="Very little text detected — image may be blurry, cropped, or edited."
                ))

            if vision.get("is_scam_likely"):
                indicators.append(FraudIndicator(
                    name="ai_flagged_suspicious_image",
                    detected=True,
                    severity="high",
                    description=vision.get("summary", "AI detected suspicious elements in the screenshot.")
                ))

            score, risk_level, confidence = calculate_scam_score(indicators)
            confidence = round((confidence + vision.get("confidence", 0.5)) / 2, 2)

            result = AnalysisResult(
                analysis_type="image",
                scam_score=score,
                risk_level=risk_level,
                confidence=confidence,
                indicators=indicators,
                recommendation=generate_recommendation(score),
                summary=vision.get("summary",
                    f"Screenshot analyzed: {word_count} words extracted, {len(indicators)} indicator(s) found."),
                extracted_data={
                    "ocr_text": extracted_text,
                    "payment_info": payment_analysis,
                    "gemini_payment_info": vision.get("payment_info", {}),
                    "key_findings": vision.get("key_findings", [])
                }
            )

        else:
            # --- Fallback: Google Cloud Vision OCR (if configured) ---
            ocr_result = await perform_ocr(request.image_base64)

            if not ocr_result.get("success"):
                # Neither vision AI is available — return a clear, non-crashing result
                result = AnalysisResult(
                    analysis_type="image",
                    scam_score=15,
                    risk_level="Low Risk",
                    confidence=0.1,
                    indicators=[FraudIndicator(
                        name="vision_ai_unavailable",
                        detected=True,
                        severity="low",
                        description="Add GOOGLE_GEMINI_API_KEY to the backend .env to enable screenshot analysis."
                    )],
                    recommendation="Set up a Gemini API key to enable full image analysis.",
                    summary=vision.get("summary", "Image analysis requires a Gemini API key. Add GOOGLE_GEMINI_API_KEY to the backend .env file.")
                )
            else:
                extracted_text   = ocr_result.get("text", "")
                payment_analysis = analyze_payment_screenshot(extracted_text)

                if not payment_analysis["contains_payment_info"]:
                    indicators.append(FraudIndicator(
                        name="no_payment_info", detected=True, severity="medium",
                        description="Image does not contain clear payment information."
                    ))
                if ocr_result.get("word_count", 0) < 5:
                    indicators.append(FraudIndicator(
                        name="insufficient_text", detected=True, severity="high",
                        description="Very little text detected — possible cropped or edited screenshot."
                    ))
                if extracted_text:
                    ai_result = await analyze_with_gemini(extracted_text, "payment screenshot text")
                    if ai_result.get("is_scam_likely"):
                        indicators.append(FraudIndicator(
                            name="suspicious_payment_content", detected=True, severity="high",
                            description=ai_result.get("summary", "Suspicious payment details detected.")
                        ))

                score, risk_level, confidence = calculate_scam_score(indicators)
                result = AnalysisResult(
                    analysis_type="image",
                    scam_score=score,
                    risk_level=risk_level,
                    confidence=round(confidence, 2),
                    indicators=indicators,
                    recommendation=generate_recommendation(score),
                    summary=f"Payment screenshot analyzed. Extracted {ocr_result.get('word_count', 0)} words.",
                    extracted_data={"ocr_text": extracted_text, "payment_info": payment_analysis}
                )

        await record_usage(request.device_id)
        return result

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Image analysis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@api_router.post("/report/submit")
async def submit_report(report: ScamReportCreate):
    try:
        if db is None:
            return {"message": "Database not available; report not saved.", "report_id": ""}

        existing = await db.scam_reports.find_one({"value": report.value, "report_type": report.report_type})

        if existing:
            await db.scam_reports.update_one(
                {"_id": existing["_id"]},
                {"$inc": {"report_count": 1}, "$set": {"updated_at": datetime.utcnow()}}
            )
            return {"message": "Report count updated for existing entry.", "report_id": existing["id"]}

        new_report = ScamReport(**report.dict())
        await db.scam_reports.insert_one(new_report.dict())
        return {"message": "Report submitted for moderation.", "report_id": new_report.id}

    except Exception as e:
        logger.error(f"Report submission error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@api_router.post("/database/search")
async def search_database(request: DatabaseSearchRequest):
    try:
        if db is None:
            return {"results": [], "count": 0}

        query_filter: Dict[str, Any] = {
            "status": {"$in": ["confirmed_scam", "user_reported"]},
            "value": {"$regex": re.escape(request.query), "$options": "i"}
        }

        if request.search_type != "all":
            query_filter["report_type"] = request.search_type

        results = await db.scam_reports.find(query_filter).limit(20).to_list(20)

        formatted = [{
            "id": r["id"],
            "type": r["report_type"],
            "value": r["value"],
            "category": r["category"],
            "status": r["status"],
            "report_count": r["report_count"],
            "description": r.get("description", "")
        } for r in results]

        return {"results": formatted, "count": len(formatted)}

    except Exception as e:
        logger.error(f"Database search error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@api_router.get("/rate-limit/{device_id}")
async def get_rate_limit(device_id: str):
    try:
        rl = await check_rate_limit(device_id)
        return rl.dict()
    except Exception as e:
        logger.error(f"Rate limit check error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@api_router.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow(),
        "daily_limit": DAILY_LIMIT
    }


app.include_router(api_router)

app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("shutdown")
async def shutdown_db_client():
    if client is not None:
        client.close()
