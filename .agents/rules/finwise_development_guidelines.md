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
