[README.md](https://github.com/user-attachments/files/29139789/README.md)
# Scam Detector AI — Flutter Setup Guide

## Prerequisites (install these first)

| Tool | Version | Install |
|---|---|---|
| Flutter SDK | 3.22+ | https://docs.flutter.dev/get-started/install |
| Dart | ships with Flutter | — |
| Python | 3.11+ | https://python.org |
| VS Code | latest | https://code.visualstudio.com |
| Flutter extension for VS Code | latest | VS Code Extensions tab |
| Android Studio (for emulator) | latest | https://developer.android.com/studio |

Verify Flutter is installed: `flutter doctor` — fix anything it flags before continuing.

---

## Step 1 — Get your API credentials

### A. Anthropic API Key
1. Go to Anthropic API Key
2. Create Key → copy it (starts with `sk-ant-`)

### B. Google Cloud API Key
1. Go to Google Cloud API Key
2. APIs & Services → Library → enable **Cloud Vision API** and **Safe Browsing API**
3. APIs & Services → Credentials → Create Credentials → API Key → copy it

### C. MongoDB Atlas (free, no local install)
1. Network Access → Add IP → Allow from Anywhere (0.0.0.0/0) for dev
2. Connect → Drivers → copy the connection string
   Format: `mongodb+srv://user:pass@cluster0.xxxxx.mongodb.net/`

---

## Step 2 — Backend setup

```bash
cd backend

# Create virtual environment
python -m venv venv

# Activate it:
# Mac/Linux:
source venv/bin/activate
# Windows:
venv\Scripts\activate

# Install deps
pip install -r requirements.txt

# Create .env from template
cp .env.example .env
# Then edit .env and fill in your 3 credentials
```

Your `backend/.env` should look like:
```
MONGO_URL="mongodb+srv://youruser:yourpassword@cluster0.xxxxx.mongodb.net/?retryWrites=true&w=majority"
DB_NAME="scam_detector_db"
ANTHROPIC_API_KEY="sk-ant-your-key-here"
GOOGLE_API_KEY="your-google-key-here"
```

Start the backend:
```bash
uvicorn server:app --reload --port 8001
```

Confirm it works: open http://localhost:8001/api/health in your browser.
You should see `{"status":"healthy",...}`

---

## Step 3 — Flutter app setup

```bash
cd flutter_app

# Copy env file
cp .env.example .env
# Edit .env and set the correct BACKEND_URL (see note below)

# Install Flutter packages
flutter pub get
```

### Setting BACKEND_URL correctly

| Where you're running the app | BACKEND_URL value |
|---|---|
| Android Emulator (AVD) | `http://10.0.2.2:8001` |
| iOS Simulator | `http://localhost:8001` |
| Physical Android/iOS via USB | `http://YOUR_LAN_IP:8001` |

To find your LAN IP:
- Windows: run `ipconfig` → look for IPv4 Address under your Wi-Fi adapter
- Mac: run `ifconfig en0` → look for `inet`
- Linux: run `ip addr show`

Your `.env` file:
```
BACKEND_URL=http://10.0.2.2:8001
```

---

## Step 4 — Run the Flutter app in VS Code

1. Open the `flutter_app` folder in VS Code (File → Open Folder)
2. Start an emulator: View → Command Palette → `Flutter: Launch Emulator`
   OR plug in a physical device with USB debugging enabled
3. Press **F5** (or Run → Start Debugging)
4. Select your device when prompted
5. The app will build and launch on your device/emulator

Alternatively from terminal:
```bash
cd flutter_app
flutter run
```

---

## Project structure

```
scam-detector-ai/
├── backend/                         ← FastAPI Python backend (unchanged)
│   ├── server.py
│   ├── requirements.txt
│   └── .env.example
│
└── flutter_app/                     ← Flutter frontend (Dart)
    ├── lib/
    │   ├── main.dart                ← Entry point, app shell, bottom nav
    │   ├── models/
    │   │   └── models.dart          ← All data classes (AnalysisResult, etc.)
    │   ├── services/
    │   │   ├── api_service.dart     ← All HTTP calls to backend
    │   │   └── app_state.dart       ← ChangeNotifier: device ID + history
    │   ├── screens/
    │   │   ├── analyze_screen.dart  ← Main screen: text/url/image analysis
    │   │   ├── database_screen.dart ← Community database search
    │   │   └── history_screen.dart  ← Local analysis history
    │   ├── widgets/
    │   │   └── result_card.dart     ← Reusable result display widget
    │   └── theme/
    │       └── app_theme.dart       ← Colors, theme, risk color helpers
    ├── android/
    │   └── app/src/main/
    │       ├── AndroidManifest.xml  ← Internet + photo permissions
    │       └── res/xml/
    │           └── network_security_config.xml  ← Allow HTTP to localhost for dev
    ├── ios/
    │   └── Runner/
    │       └── Info.plist           ← Photo library permission string
    ├── pubspec.yaml                 ← Flutter dependencies
    ├── .env.example                 ← Copy to .env
    └── .env                         ← YOUR local config — never share or commit
```

---

## Common issues

| Problem | Fix |
|---|---|
| `flutter doctor` shows issues | Fix each one before running the app |
| `Connection refused` on Android emulator | Use `http://10.0.2.2:8001` not `localhost` |
| `Connection refused` on physical device | Use your LAN IP, not `localhost` |
| `CLEARTEXT communication not permitted` | Your LAN IP is not in `network_security_config.xml` — add it |
| `401` from Anthropic | Wrong `ANTHROPIC_API_KEY` in `backend/.env` |
| `403` from Google Vision | Cloud Vision API not enabled in Google Cloud Console |
| MongoDB connection error | Check Atlas connection string and IP whitelist |
| `MissingPluginException` (image_picker) | Run `flutter clean && flutter pub get`, restart |

---

## Security — read this

- NEVER commit `.env` files to Git — add to `.gitignore`
- NEVER paste your API keys in chat, screenshots, or documents
- NEVER share `backend/.env` or `flutter_app/.env`
- The `.env.example` files are safe to commit — they contain only placeholders
