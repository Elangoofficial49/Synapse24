from pydantic import BaseModel, EmailStr, Field, ConfigDict, field_validator
from typing import Optional, List, Dict, Any
from datetime import datetime, date
from app.models import (
    OrgType, UserRole, BatchStatus, PackageStatus, ShipmentStatus,
    CustodyEventType, AlertType, AlertSeverity, AlertReviewStatus,
    DisputeStatus, RecallSeverity, RecallStatus, BlockchainTxStatus
)

# Common
class ResponseBase(BaseModel):
    model_config = ConfigDict(from_attributes=True)

# Auth
class LoginRequest(BaseModel):
    email: EmailStr
    password: str

class RegistrationRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=10, max_length=128)
    full_name: str = Field(min_length=1, max_length=255)
    organization_name: str = Field(min_length=1, max_length=255)
    organization_type: OrgType
    license_number: str = Field(min_length=1, max_length=100)
    address: str = Field(min_length=1, max_length=500)
    contact_email: EmailStr

    @field_validator("password")
    @classmethod
    def validate_password_bcrypt_length(cls, password: str) -> str:
        if len(password.encode("utf-8")) > 72:
            raise ValueError("Password must not exceed 72 UTF-8 bytes")
        return password

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: Dict[str, Any]

class RegistrationResponse(BaseModel):
    message: str
    status: str

class PendingUserResponse(BaseModel):
    id: str
    email: EmailStr
    full_name: str
    role: UserRole
    organization_id: str
    organization_name: str
    organization_type: OrgType
    license_number: str
    contact_email: EmailStr
    created_at: datetime

class UserCreate(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    organization_id: str
    role: UserRole

class UserResponse(ResponseBase):
    id: str
    email: str
    full_name: str
    organization_id: str
    role: UserRole
    is_active: bool
    created_at: datetime

# Organization
class OrganizationCreate(BaseModel):
    name: str
    org_type: OrgType
    license_number: str
    address: str
    contact_email: EmailStr

class OrganizationResponse(ResponseBase):
    id: str
    name: str
    org_type: OrgType
    license_number: str
    address: str
    contact_email: str
    is_active: bool
    created_at: datetime

# Product
class ProductCreate(BaseModel):
    name: str
    generic_name: str
    product_code: str
    dosage_form: str
    strength: str
    description: Optional[str] = None

class ProductResponse(ResponseBase):
    id: str
    name: str
    generic_name: str
    manufacturer_id: str
    product_code: str
    dosage_form: str
    strength: str
    description: Optional[str] = None
    is_active: bool
    created_at: datetime

# Batch
class BatchCreate(BaseModel):
    product_id: str
    batch_number: str
    manufacturing_date: date
    expiry_date: date
    quantity_manufactured: int = Field(gt=0)

class BatchResponse(ResponseBase):
    id: str
    product_id: str
    batch_number: str
    manufacturing_date: date
    expiry_date: date
    quantity_manufactured: int
    status: BatchStatus
    recall_reason: Optional[str] = None
    created_at: datetime

# SerializedPackage
class PackageGenerateRequest(BaseModel):
    batch_id: str
    count: int = Field(gt=0, le=500, default=100)

class SerializedPackageResponse(ResponseBase):
    id: str
    package_serial_id: str
    batch_id: str
    current_custodian_org_id: str
    status: PackageStatus
    qr_code_data: str
    created_at: datetime

class PackageVerificationResponse(BaseModel):
    is_valid: bool
    package_serial_id: str
    status: Optional[str] = None
    product_name: Optional[str] = None
    generic_name: Optional[str] = None
    product_code: Optional[str] = None
    description: Optional[str] = None
    dosage_form: Optional[str] = None
    strength: Optional[str] = None
    batch_number: Optional[str] = None
    manufacturing_date: Optional[date] = None
    expiry_date: Optional[date] = None
    manufacturer_name: Optional[str] = None
    package_created_at: Optional[datetime] = None
    is_expired: bool = False
    is_recalled: bool = False
    is_quarantined: bool = False
    current_custodian: Optional[str] = None
    warning_message: Optional[str] = None
    custody_events_count: int = 0
    recent_events: List[Dict[str, Any]] = []

# Shipment
class ShipmentCreate(BaseModel):
    receiver_org_id: str
    transporter_org_id: Optional[str] = None
    package_serial_ids: List[str] = Field(min_length=1)
    notes: Optional[str] = None

class ShipmentResponse(ResponseBase):
    id: str
    shipment_reference: str
    sender_org_id: str
    receiver_org_id: str
    transporter_org_id: Optional[str] = None
    status: ShipmentStatus
    declared_quantity: int
    received_quantity: Optional[int] = None
    dispatch_timestamp: Optional[datetime] = None
    receipt_timestamp: Optional[datetime] = None
    notes: Optional[str] = None
    parent_shipment_id: Optional[str] = None
    created_at: datetime

class ShipmentReceiveRequest(BaseModel):
    actual_quantity_received: int = Field(ge=0)
    scanned_package_serial_ids: Optional[List[str]] = None
    notes: Optional[str] = None

class ShipmentSplitRequest(BaseModel):
    child_shipments: List[Dict[str, Any]] # [{"receiver_org_id": "...", "package_serial_ids": [...]}]

# Custody Event
class CustodyEventResponse(ResponseBase):
    id: str
    package_id: str
    shipment_id: Optional[str] = None
    event_type: CustodyEventType
    from_org_id: Optional[str] = None
    to_org_id: Optional[str] = None
    performed_by: str
    event_timestamp: datetime
    quantity_involved: Optional[int] = None
    notes: Optional[str] = None
    blockchain_tx_ref: Optional[str] = None
    is_on_chain: bool
    created_at: datetime

# Alerts
class AlertResponse(ResponseBase):
    id: str
    alert_type: AlertType
    severity: AlertSeverity
    package_id: Optional[str] = None
    shipment_id: Optional[str] = None
    reason: str
    evidence_json: Optional[Dict[str, Any]] = None
    review_status: AlertReviewStatus
    assigned_to: Optional[str] = None
    investigator_notes: Optional[str] = None
    resolution_outcome: Optional[str] = None
    created_at: datetime

class AlertReviewUpdate(BaseModel):
    review_status: AlertReviewStatus
    investigator_notes: Optional[str] = None
    resolution_outcome: Optional[str] = None

# Dispute
class DisputeCreate(BaseModel):
    shipment_id: str
    dispute_reason: str
    expected_quantity: int
    actual_quantity: int

class DisputeResolveRequest(BaseModel):
    resolution_notes: str
    status: DisputeStatus = DisputeStatus.RESOLVED
    correction_justification: Optional[str] = None

class DisputeResponse(ResponseBase):
    id: str
    shipment_id: str
    reported_by: str
    assigned_to: Optional[str] = None
    dispute_reason: str
    expected_quantity: int
    actual_quantity: int
    status: DisputeStatus
    resolution_notes: Optional[str] = None
    resolved_by: Optional[str] = None
    resolved_at: Optional[datetime] = None
    created_at: datetime

# Recall
class RecallCreate(BaseModel):
    batch_id: str
    recall_reason: str
    severity: RecallSeverity = RecallSeverity.MANDATORY

class RecallResponse(ResponseBase):
    id: str
    batch_id: str
    initiated_by: str
    recall_reason: str
    severity: RecallSeverity
    affected_package_count: Optional[int] = None
    status: RecallStatus
    investigation_notes: Optional[str] = None
    resolved_at: Optional[datetime] = None
    created_at: datetime
