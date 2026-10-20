# FinWise Development & Runtime Guidelines

## 1. Feature Implementation Workflow
- ALWAYS outline the technical plan and architecture before writing code.
- When introducing AI / ML models: explicitly specify the model name, author/organization (e.g., Clova AI / VinAI), license, and hardware requirements (GPU VRAM / CUDA). Wait for user approval before installation.

## 2. Windows Flutter & Browser Execution
- For Flutter Web preview on Windows: default to Microsoft Edge (`flutter run -d edge`).
- Do NOT use Brave as Chrome replacement with CDP `--remote-debugging-port`, as Brave Shields blocks debugger communication and causes timeout after 30s.

## 3. Python & EasyOCR on Windows PowerShell
- Always set UTF-8 encoding in Python scripts (`sys.stdout.reconfigure(encoding='utf-8')` or `-X utf8`).
- When initializing EasyOCR, pass `verbose=False` to prevent Windows cp1252 `UnicodeEncodeError` on progress bar characters (`\u2588`).

## 4. Bill & Receipt OCR Parsing Rules
- Always use bilingual recognition: `easyocr.Reader(['vi', 'en'])`.
- Merge horizontally adjacent bounding boxes (shared Y-coordinate) before keyword parsing.
- Exclude receipt headers (`HÓA ĐƠN THANH TOÁN`, `RECEIPT`, `INVOICE`) from total amount keyword searches.
- Parse amounts using reverse pattern matching to prevent combining item quantity with unit price.
- Support OCR character confusion recovery (replace 'o'/'O' with '0' inside numbers).

## 5. Windows PowerShell Execution
- In Windows PowerShell, do NOT use `&&` to chain multiple commands (causes `ParserError: The token '&&' is not a valid statement separator`).
- ALWAYS use `;` (semicolon) to separate sequential commands in PowerShell.

## 6. Monorepo Cloud Deployment (Render.com)
- When deploying the Node.js backend from a monorepo containing multiple subdirectories (`backend`, `ai_service`, `finwise_mobile`), ALWAYS configure the Web Service **Root Directory** as `backend`.
- This ensures Render's build process locates `package.json` correctly and prevents `ENOENT` build failure.

## 7. Role-Based Access Control (RBAC) & Admin Actor
- Default Root Admin: `admin@finwise.com` / `admin123456`.
- Root Admin Protection: The system must NEVER allow deleting or suspending the root administrator account.
- Security & Privacy: Admin APIs must be guarded by `verifyAdmin` middleware. The Admin dashboard provides aggregate health monitoring (KPIs, AI services, user status) without exposing sensitive personal transaction records.
- Mobile Flow: Provide a 1-tap Admin demo button on the login screen for seamless defense presentations.

## 8. Continuous Deployment & Real-World APK Release Cycle
- **Backend & AI updates**: Deploy by pushing to GitHub (`git push origin main`); Render automatically redeploys. Existing mobile APKs receive updates immediately without reinstallation.
- **Flutter UI updates**: Run `START_ALL.bat` option 3 (`flutter build apk --release`). Installing the new APK over the existing app preserves user sessions and cloud data.

