# PharmaTrace — Blockchain-Backed Pharmaceutical Supply Chain Traceability

PharmaTrace is an enterprise full-stack pharmaceutical traceability platform featuring:
- **FastAPI Python Backend** with SQLAlchemy 2.0 ORM, JWT Auth, and RBAC
- **Hyperledger Fabric Smart Contracts (Go Chaincode)** with dedicated adapter boundary and verifiable test adapter
- **Flutter Web & Mobile Application** featuring custom enterprise design system
- **PostgreSQL Database** with automated schema definitions and synthetic demo seed dataset
- **Four Core Innovations**:
  1. Strict Two-Party Custody Verification (Sender Dispatch vs. Receiver Acceptance)
  2. Suspicious Scan & Anomaly Detection (duplicate scans, unauthorized sequence, recalled transfers)
  3. Shipment Splitting & Quantity Reconciliation (parent-child allocation rules)
  4. Dispute Resolution & Append-Only Correction History (preserves historical ledger transactions)

---

## Architecture Overview

```
synapse24/
├── backend/                   # Python FastAPI Backend
│   ├── app/
│   │   ├── api/routes/        # Auth, Products, Shipments, Compliance, Analytics, QR
│   │   ├── blockchain/        # BlockchainInterface, TestBlockchainAdapter, FabricAdapter
│   │   ├── core/              # Config, Security (bcrypt/JWT), Permissions (RBAC)
│   │   ├── db/                # Async & Sync DB session & Base mixins
│   │   ├── models/            # SQLAlchemy ORM Models
│   │   ├── schemas/           # Pydantic v2 validation models
│   │   ├── services/          # PharmaService, CustodyService, DisputeService, RecallService
│   │   └── main.py            # FastAPI Entry Point & Lifespan
│   ├── tests/                 # Pytest E2E Custody & Auth test suite
│   ├── seed.py                # Synthetic demo pharmaceutical dataset
│   └── requirements.txt
├── frontend/                  # Flutter Web Frontend
│   ├── lib/
│   │   ├── core/              # Enterprise Material 3 theme & color system
│   │   ├── models/            # Serialized entity models
│   │   ├── screens/           # LandingPage (instant QR verify), LoginPage, DashboardPage
│   │   ├── services/          # Dio API Client with Bearer token interceptor
│   │   └── main.dart          # Flutter App root
│   └── test/                  # Widget tests
├── blockchain/
│   └── chaincode/             # Hyperledger Fabric Go chaincode (pharmatrace.go)
├── docker-compose.yml         # Containerized production stack
└── README.md
```

---

## Quickstart Instructions

### Configure private environment files

Copy the ignored templates before starting the services:

```powershell
if (!(Test-Path .env)) { Copy-Item .env.example .env }
if (!(Test-Path backend\.env)) { Copy-Item backend\.env.example backend\.env }
```

The root `.env` configures PostgreSQL for Docker Compose. `backend\.env` holds
the backend signing key and Brevo credentials; the local Python backend uses
SQLite by default. Replace the placeholder Brevo settings with your verified
Brevo sender details. Never commit either `.env` file.

### 1. Run the Python Backend

```powershell
cd backend

# Install dependencies (if not already installed)
python -m pip install -r requirements.txt

# Seed the database with sample organizations, products, and batches
python seed.py

# Launch FastAPI server
uvicorn app.main:app --reload --port 8000
```
- Swagger OpenAPI documentation: `http://localhost:8000/docs`
- Health check endpoint: `http://localhost:8000/health`

### Configure email verification for registration

Organization registration requires verifying the sign-in email with a six-digit
code sent through the Brevo SMTP API. Set these variables in `backend/.env`
(keep this file private and never commit the API key):

```dotenv
BREVO_API_KEY=your_brevo_api_key
BREVO_SENDER_EMAIL=verified-sender@example.com
BREVO_SENDER_NAME=PharmaTrace
```

The sender address must be verified in Brevo. Restart the backend after adding
the settings. Codes expire after 10 minutes, are limited to five attempts, and
must be verified before the registration can be submitted. Registration
passwords must be at least 10 characters and include uppercase and lowercase
letters, a number, and a symbol.

### Role-based traceability

- **Manufacturer:** Sign in and open **Manufacturer dashboard** for batch overview and inventory, product and batch registration, QR generation, distributor verification details, dispatches, pending receipts, batch verification, recalls, audit history, documents, and alerts. Dispatch and recall actions are restricted to the manufacturer's own inventory. Quality certificates and test reports can be uploaded as PDF, PNG, or JPEG files up to 10 MB and are stored off-chain in the private document directory.
- **Distributor, transporter, pharmacy, and hospital users:** Open **Scan QR** in the console, or use the public scanner on the landing page, to view package details and custody tracking. Camera scanning requires camera permission; a package URL or serial ID can also be entered manually.
- **Distributors:** The **Distributor dashboard** provides incoming and outgoing shipment summaries, QR-scanned receipt confirmation, inventory, a verified pharmacy directory, pharmacy orders and dispatches, pending pharmacy receipts, transfer history, batch verification, recall/quarantine status, suspicious scan reports, and notifications. Pharmacy orders select serialized package quantities from available inventory and record the receiving pharmacy in the custody transfer. Scanned packages are verified against the selected shipment before receipt is confirmed; discrepancies require a reason and are recorded with the receipt transaction. The separate **Wholesaler partners** dashboard remains available for distributor-to-distributor transfers.
- **New organizations:** Select **Register** on the landing page or **Register a company account** on the sign-in screen. The account remains pending until a system administrator approves the organization. Administrators can review requests under **Account approvals**.

### 2. Run the Flutter Frontend

```powershell
cd frontend

# Get Flutter dependencies
flutter pub get

# Run on Chrome (Web)
flutter run -d chrome
```

---

## Demo Accounts (Development Only)

| Role | Email | Password |
|---|---|---|
| **System Admin** | `admin@pharmatrace.dev` | `DevAdmin2024!` |
| **Manufacturer** | `manufacturer@pharmatrace.dev` | `DevMfr2024!` |
| **Distributor** | `distributor@pharmatrace.dev` | `DevDist2024!` |
| **Pharmacy / Hospital** | `pharmacy@pharmatrace.dev` | `DevRx2024!` |
| **Auditor / Regulator** | `auditor@pharmatrace.dev` | `DevAudit2024!` |

---

## Verifying the 4 Core Innovations

1. **Two-Party Custody Verification**:
   - Manufacturer creates a shipment declaring 5 units.
   - Distributor navigates to the *Shipments* tab on the Dashboard and clicks **Receive Shipment**.
   - Distributor enters 4 units instead of 5.
   - The system records partial receipt, creates a discrepancy record, and automatically files a formal Dispute.

2. **Suspicious Scan Detection**:
   - Scan an unregistered package (e.g. `PT-FAKE-000`) on the Landing Page.
   - The system marks it as unverified, displays a critical alert banner, and logs a `SuspiciousActivityAlert` under the Anomaly Monitoring center.

3. **Shipment Splitting & Quantity Reconciliation**:
   - The endpoint `POST /api/v1/shipments/{id}/split` validates that the sum of child shipments does not exceed verified received inventory.

4. **Append-Only Dispute Resolution**:
   - Authorized auditors resolve disputes by recording `CorrectionEvent` entries with justification notes without mutating original ledger custody event logs.

---

## Automated Test Execution

### Backend Pytest Suite
```powershell
cd backend
python -m pytest tests/test_e2e_custody.py
```
*Result: 5 passed in 1.93s*

### Frontend Flutter Test Suite
```powershell
cd frontend
flutter test
```
*Result: All tests passed!*

---

## Blockchain Configuration Status
- **Current Mode**: `test` (`BLOCKCHAIN_MODE=test` in `.env`). Simulated via `TestBlockchainAdapter`.
- **Production Mode**: To connect to a live Hyperledger Fabric peer, deploy `blockchain/chaincode/pharmatrace.go`, configure connection certificates, and set `BLOCKCHAIN_MODE=fabric`.
