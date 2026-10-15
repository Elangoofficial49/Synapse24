import enum
from typing import Optional, List
from datetime import datetime, date
from sqlalchemy import (
    String, Integer, Boolean, DateTime, Date, Enum, ForeignKey, 
    Text, JSON, Float, UniqueConstraint, Index
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base, UUIDPrimaryKeyMixin, TimestampMixin

# Enums
class OrgType(str, enum.Enum):
    MANUFACTURER = "manufacturer"
    DISTRIBUTOR = "distributor"
    TRANSPORTER = "transporter"
    PHARMACY = "pharmacy"
    HOSPITAL = "hospital"
    REGULATOR = "regulator"

class UserRole(str, enum.Enum):
    ADMIN = "admin"
    MANUFACTURER = "manufacturer"
    DISTRIBUTOR = "distributor"
    TRANSPORTER = "transporter"
    PHARMACY_STAFF = "pharmacy_staff"
    AUDITOR = "auditor"

class BatchStatus(str, enum.Enum):
    ACTIVE = "active"
    RECALLED = "recalled"
    QUARANTINED = "quarantined"
    EXPIRED = "expired"

class PackageStatus(str, enum.Enum):
    MANUFACTURED = "manufactured"
    IN_TRANSIT = "in_transit"
    RECEIVED = "received"
    DISPENSED = "dispensed"
    RECALLED = "recalled"
    QUARANTINED = "quarantined"
    DISPOSED = "disposed"

class ShipmentStatus(str, enum.Enum):
    DRAFT = "draft"
    DISPATCHED = "dispatched"
    IN_TRANSIT = "in_transit"
    DELIVERED = "delivered"
    RECEIVED = "received"
    PARTIALLY_RECEIVED = "partially_received"
    REJECTED = "rejected"
    DISPUTED = "disputed"

class CustodyEventType(str, enum.Enum):
    MANUFACTURED = "manufactured"
    DISPATCHED = "dispatched"
    PICKUP = "pickup"
    IN_TRANSIT = "in_transit"
    DELIVERED = "delivered"
    RECEIVED = "received"
    PARTIALLY_RECEIVED = "partially_received"
    REJECTED = "rejected"
    DISPUTED = "disputed"
    SPLIT = "split"
    RECALLED = "recalled"
    QUARANTINED = "quarantined"
    DISPENSED = "dispensed"
    CORRECTION = "correction"

class AlertType(str, enum.Enum):
    REPEATED_SCAN = "repeated_scan"
    DUPLICATE_SCAN = "duplicate_scan"
    UNAUTHORIZED_SCAN = "unauthorized_scan"
    INVALID_SEQUENCE = "invalid_sequence"
    RECALLED_TRANSFER = "recalled_transfer"
    EXPIRED_SCAN = "expired_scan"
    CONFLICTING_TRANSFER = "conflicting_transfer"
    UNKNOWN_PACKAGE = "unknown_package"
    CUSTODY_MISMATCH = "custody_mismatch"
    SUSPICIOUS_REPORT = "suspicious_report"

class AlertSeverity(str, enum.Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

class AlertReviewStatus(str, enum.Enum):
    OPEN = "open"
    UNDER_REVIEW = "under_review"
    RESOLVED = "resolved"
    FALSE_POSITIVE = "false_positive"

class DisputeStatus(str, enum.Enum):
    OPEN = "open"
    UNDER_INVESTIGATION = "under_investigation"
    RESOLVED = "resolved"
    ESCALATED = "escalated"

class RecallSeverity(str, enum.Enum):
    VOLUNTARY = "voluntary"
    MANDATORY = "mandatory"
    PRECAUTIONARY = "precautionary"

class RecallStatus(str, enum.Enum):
    ACTIVE = "active"
    RESOLVED = "resolved"
    CLOSED = "closed"

class BlockchainTxStatus(str, enum.Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    FAILED = "failed"
    TEST_MODE = "test_mode"


# Models
class Organization(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "organizations"

    name: Mapped[str] = mapped_column(String(255), nullable=False)
    org_type: Mapped[OrgType] = mapped_column(Enum(OrgType), nullable=False)
    license_number: Mapped[str] = mapped_column(String(100), unique=True, index=True, nullable=False)
    address: Mapped[str] = mapped_column(String(500), nullable=False)
    contact_email: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    users: Mapped[List["User"]] = relationship("User", back_populates="organization")


class User(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    organization_id: Mapped[str] = mapped_column(String(36), ForeignKey("organizations.id"), nullable=False)
    role: Mapped[UserRole] = mapped_column(Enum(UserRole), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    last_login: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    organization: Mapped["Organization"] = relationship("Organization", back_populates="users")


class RegistrationEmailVerification(Base):
    __tablename__ = "registration_email_verifications"

    email: Mapped[str] = mapped_column(String(255), primary_key=True)
    code_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    sent_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    verified_until: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)


class Product(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "products"

    name: Mapped[str] = mapped_column(String(255), nullable=False)
    generic_name: Mapped[str] = mapped_column(String(255), nullable=False)
    manufacturer_id: Mapped[str] = mapped_column(String(36), ForeignKey("organizations.id"), nullable=False)
    product_code: Mapped[str] = mapped_column(String(100), unique=True, index=True, nullable=False)
    dosage_form: Mapped[str] = mapped_column(String(100), nullable=False) # Tablet, Capsule, Syrup, etc.
    strength: Mapped[str] = mapped_column(String(100), nullable=False) # e.g. 500mg
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    batches: Mapped[List["Batch"]] = relationship("Batch", back_populates="product")


class Batch(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "batches"

    product_id: Mapped[str] = mapped_column(String(36), ForeignKey("products.id"), nullable=False)
    batch_number: Mapped[str] = mapped_column(String(100), index=True, nullable=False)
    manufacturing_date: Mapped[date] = mapped_column(Date, nullable=False)
    expiry_date: Mapped[date] = mapped_column(Date, index=True, nullable=False)
    quantity_manufactured: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[BatchStatus] = mapped_column(Enum(BatchStatus), default=BatchStatus.ACTIVE, nullable=False)
    recall_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_by: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)

    __table_args__ = (
        UniqueConstraint("product_id", "batch_number", name="uq_product_batch_number"),
    )

    product: Mapped["Product"] = relationship("Product", back_populates="batches")
    packages: Mapped[List["SerializedPackage"]] = relationship("SerializedPackage", back_populates="batch")


class BatchDocument(Base, UUIDPrimaryKeyMixin):
    __tablename__ = "batch_documents"

    batch_id: Mapped[str] = mapped_column(String(36), ForeignKey("batches.id"), index=True, nullable=False)
    organization_id: Mapped[str] = mapped_column(String(36), ForeignKey("organizations.id"), index=True, nullable=False)
    uploaded_by: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    original_filename: Mapped[str] = mapped_column(String(255), nullable=False)
    stored_filename: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    content_type: Mapped[str] = mapped_column(String(100), nullable=False)
    file_size: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class SerializedPackage(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "serialized_packages"

    package_serial_id: Mapped[str] = mapped_column(String(150), unique=True, index=True, nullable=False)
    batch_id: Mapped[str] = mapped_column(String(36), ForeignKey("batches.id"), nullable=False)
    current_custodian_org_id: Mapped[str] = mapped_column(String(36), ForeignKey("organizations.id"), nullable=False)
    status: Mapped[PackageStatus] = mapped_column(Enum(PackageStatus), default=PackageStatus.MANUFACTURED, nullable=False)
    qr_code_data: Mapped[str] = mapped_column(Text, nullable=False)

    batch: Mapped["Batch"] = relationship("Batch", back_populates="packages")
    custody_events: Mapped[List["CustodyEvent"]] = relationship("CustodyEvent", back_populates="package")


class Shipment(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "shipments"

    shipment_reference: Mapped[str] = mapped_column(String(100), unique=True, index=True, nullable=False)
    sender_org_id: Mapped[str] = mapped_column(String(36), ForeignKey("organizations.id"), nullable=False)
    receiver_org_id: Mapped[str] = mapped_column(String(36), ForeignKey("organizations.id"), nullable=False)
    transporter_org_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("organizations.id"), nullable=True)
    status: Mapped[ShipmentStatus] = mapped_column(Enum(ShipmentStatus), default=ShipmentStatus.DRAFT, nullable=False)
    declared_quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    received_quantity: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    dispatch_timestamp: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    receipt_timestamp: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    parent_shipment_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("shipments.id"), nullable=True)
    created_by: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)

    items: Mapped[List["ShipmentItem"]] = relationship("ShipmentItem", back_populates="shipment")


class ShipmentItem(Base, UUIDPrimaryKeyMixin):
    __tablename__ = "shipment_items"

    shipment_id: Mapped[str] = mapped_column(String(36), ForeignKey("shipments.id"), nullable=False)
    package_id: Mapped[str] = mapped_column(String(36), ForeignKey("serialized_packages.id"), nullable=False)
    quantity_dispatched: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    quantity_received: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    status: Mapped[str] = mapped_column(String(50), default="dispatched")

    shipment: Mapped["Shipment"] = relationship("Shipment", back_populates="items")


class CustodyEvent(Base, UUIDPrimaryKeyMixin):
    __tablename__ = "custody_events"

    package_id: Mapped[str] = mapped_column(String(36), ForeignKey("serialized_packages.id"), index=True, nullable=False)
    shipment_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("shipments.id"), nullable=True)
    event_type: Mapped[CustodyEventType] = mapped_column(Enum(CustodyEventType), nullable=False)
    from_org_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("organizations.id"), nullable=True)
    to_org_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("organizations.id"), nullable=True)
    performed_by: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    event_timestamp: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True, nullable=False)
    quantity_involved: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    blockchain_tx_ref: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    is_on_chain: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

    package: Mapped["SerializedPackage"] = relationship("SerializedPackage", back_populates="custody_events")


class QRScanEvent(Base, UUIDPrimaryKeyMixin):
    __tablename__ = "qr_scan_events"

    package_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("serialized_packages.id"), nullable=True)
    raw_scanned_data: Mapped[str] = mapped_column(Text, nullable=False)
    scanned_by: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("users.id"), nullable=True)
    scan_timestamp: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True, nullable=False)
    scan_location_note: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    is_valid: Mapped[bool] = mapped_column(Boolean, default=False)
    result_message: Mapped[str] = mapped_column(String(500), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class SuspiciousActivityAlert(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "suspicious_activity_alerts"

    alert_type: Mapped[AlertType] = mapped_column(Enum(AlertType), nullable=False)
    severity: Mapped[AlertSeverity] = mapped_column(Enum(AlertSeverity), nullable=False)
    package_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("serialized_packages.id"), nullable=True)
    shipment_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("shipments.id"), nullable=True)
    triggered_by_scan_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("qr_scan_events.id"), nullable=True)
    reason: Mapped[str] = mapped_column(String(500), nullable=False)
    evidence_json: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    review_status: Mapped[AlertReviewStatus] = mapped_column(Enum(AlertReviewStatus), default=AlertReviewStatus.OPEN, nullable=False)
    assigned_to: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("users.id"), nullable=True)
    investigator_notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    resolution_outcome: Mapped[Optional[str]] = mapped_column(Text, nullable=True)


class Dispute(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "disputes"

    shipment_id: Mapped[str] = mapped_column(String(36), ForeignKey("shipments.id"), nullable=False)
    reported_by: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    assigned_to: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("users.id"), nullable=True)
    dispute_reason: Mapped[str] = mapped_column(String(500), nullable=False)
    expected_quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    actual_quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    unit_of_measure: Mapped[str] = mapped_column(String(50), default="units", nullable=False)
    evidence_hash: Mapped[Optional[str]] = mapped_column(String(64), nullable=True) # SHA-256 hash of evidence document
    evidence_reference: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    status: Mapped[DisputeStatus] = mapped_column(Enum(DisputeStatus), default=DisputeStatus.OPEN, nullable=False)
    resolution_notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    resolved_by: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("users.id"), nullable=True)
    resolved_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    corrections: Mapped[List["CorrectionEvent"]] = relationship("CorrectionEvent", back_populates="dispute")


class CorrectionEvent(Base, UUIDPrimaryKeyMixin):
    __tablename__ = "correction_events"

    dispute_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("disputes.id"), nullable=True)
    shipment_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("shipments.id"), nullable=True)
    package_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("serialized_packages.id"), nullable=True)
    correction_type: Mapped[str] = mapped_column(String(100), nullable=False)
    corrected_by: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    original_value: Mapped[str] = mapped_column(String(255), nullable=False)
    corrected_value: Mapped[str] = mapped_column(String(255), nullable=False)
    justification: Mapped[str] = mapped_column(Text, nullable=False)
    blockchain_tx_ref: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

    dispute: Mapped[Optional["Dispute"]] = relationship("Dispute", back_populates="corrections")


class Recall(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "recalls"

    batch_id: Mapped[str] = mapped_column(String(36), ForeignKey("batches.id"), nullable=False)
    initiated_by: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    recall_reason: Mapped[str] = mapped_column(Text, nullable=False)
    severity: Mapped[RecallSeverity] = mapped_column(Enum(RecallSeverity), default=RecallSeverity.MANDATORY, nullable=False)
    affected_package_count: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    status: Mapped[RecallStatus] = mapped_column(Enum(RecallStatus), default=RecallStatus.ACTIVE, nullable=False)
    investigation_notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    resolved_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)


class RecallAcknowledgement(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "recall_acknowledgements"

    recall_id: Mapped[str] = mapped_column(String(36), ForeignKey("recalls.id"), nullable=False)
    organization_id: Mapped[str] = mapped_column(String(36), ForeignKey("organizations.id"), nullable=False)
    acknowledged_by: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False)
    quarantined_quantity: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    response_notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    blockchain_tx_ref: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)


class Notification(Base, UUIDPrimaryKeyMixin):
    __tablename__ = "notifications"

    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), index=True, nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    notification_type: Mapped[str] = mapped_column(String(50), default="info")
    related_entity_type: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    related_entity_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class AuditLog(Base, UUIDPrimaryKeyMixin):
    __tablename__ = "audit_logs"

    user_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("users.id"), index=True, nullable=True)
    action: Mapped[str] = mapped_column(String(100), index=True, nullable=False)
    entity_type: Mapped[str] = mapped_column(String(100), nullable=False)
    entity_id: Mapped[Optional[str]] = mapped_column(String(36), nullable=True)
    ip_address: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    user_agent: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    request_details: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    result: Mapped[str] = mapped_column(String(50), default="success") # success, failure, unauthorized
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True, nullable=False)


class LedgerTransactionReference(Base, UUIDPrimaryKeyMixin):
    __tablename__ = "ledger_transaction_references"

    tx_id: Mapped[str] = mapped_column(String(100), unique=True, index=True, nullable=False)
    channel_name: Mapped[str] = mapped_column(String(100), default="pharmachannel")
    chaincode_name: Mapped[str] = mapped_column(String(100), default="pharmatrace")
    function_name: Mapped[str] = mapped_column(String(100), nullable=False)
    status: Mapped[BlockchainTxStatus] = mapped_column(Enum(BlockchainTxStatus), default=BlockchainTxStatus.TEST_MODE)
    blockchain_mode: Mapped[str] = mapped_column(String(20), default="test") # test or fabric
    payload_hash: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    response_payload: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    confirmed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
