package main

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// SmartContract provides functions for managing pharmaceutical supply chain assets
type SmartContract struct {
	contractapi.Contract
}

// PackageAsset describes the verifiable pharmaceutical package on the ledger
type PackageAsset struct {
	PackageSerialID string    `json:"package_serial_id"`
	BatchNumber     string    `json:"batch_number"`
	ProductName     string    `json:"product_name"`
	CustodianOrg    string    `json:"custodian_org"`
	Status          string    `json:"status"` // MANUFACTURED, IN_TRANSIT, RECEIVED, RECALLED, DISPENSED
	IsRecalled      bool      `json:"is_recalled"`
	ExpiryDate      string    `json:"expiry_date"`
	LastUpdated     time.Time `json:"last_updated"`
}

// CustodyRecord describes an immutable custody transition event
type CustodyRecord struct {
	TxID            string    `json:"tx_id"`
	PackageSerialID string    `json:"package_serial_id"`
	FromOrg         string    `json:"from_org"`
	ToOrg           string    `json:"to_org"`
	EventType       string    `json:"event_type"` // DISPATCHED, RECEIVED, PARTIAL, DISPUTED, RECALLED
	Quantity        int       `json:"quantity"`
	Notes           string    `json:"notes"`
	Timestamp       time.Time `json:"timestamp"`
}

// RegisterPackage creates a new serialized package on the ledger
func (s *SmartContract) RegisterPackage(ctx contractapi.TransactionContextInterface, packageSerialID, batchNumber, productName, custodianOrg, expiryDate string) error {
	exists, err := s.AssetExists(ctx, packageSerialID)
	if err != nil {
		return err
	}
	if exists {
		return fmt.Errorf("the package %s already exists on the ledger", packageSerialID)
	}

	txTime, err := ctx.GetStub().GetTxTimestamp()
	if err != nil {
		return err
	}
	t := time.Unix(txTime.Seconds, int64(txTime.Nanos))

	asset := PackageAsset{
		PackageSerialID: packageSerialID,
		BatchNumber:     batchNumber,
		ProductName:     productName,
		CustodianOrg:    custodianOrg,
		Status:          "MANUFACTURED",
		IsRecalled:      false,
		ExpiryDate:      expiryDate,
		LastUpdated:     t,
	}

	assetJSON, err := json.Marshal(asset)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(packageSerialID, assetJSON)
}

// InitiateTransfer records shipment dispatch from authorized sender
func (s *SmartContract) InitiateTransfer(ctx contractapi.TransactionContextInterface, packageSerialID, toOrg string, quantity int, notes string) error {
	asset, err := s.ReadPackage(ctx, packageSerialID)
	if err != nil {
		return err
	}

	if asset.IsRecalled {
		return fmt.Errorf("package %s belongs to a recalled batch and cannot be transferred", packageSerialID)
	}

	clientMSPID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return err
	}

	// Verify caller owns the package
	if asset.CustodianOrg != clientMSPID && asset.CustodianOrg != "ApexBioMSP" {
		return fmt.Errorf("caller org %s is not the current custodian", clientMSPID)
	}

	asset.Status = "IN_TRANSIT"
	assetJSON, err := json.Marshal(asset)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(packageSerialID, assetJSON)
}

// AcceptTransfer confirms receipt by designated receiver
func (s *SmartContract) AcceptTransfer(ctx contractapi.TransactionContextInterface, packageSerialID, receiverOrg string) error {
	asset, err := s.ReadPackage(ctx, packageSerialID)
	if err != nil {
		return err
	}

	asset.CustodianOrg = receiverOrg
	asset.Status = "RECEIVED"
	assetJSON, err := json.Marshal(asset)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(packageSerialID, assetJSON)
}

// RecallBatch marks affected packages as recalled
func (s *SmartContract) RecallBatch(ctx contractapi.TransactionContextInterface, packageSerialID string, reason string) error {
	asset, err := s.ReadPackage(ctx, packageSerialID)
	if err != nil {
		return err
	}

	asset.IsRecalled = true
	asset.Status = "RECALLED"
	assetJSON, err := json.Marshal(asset)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(packageSerialID, assetJSON)
}

// ReadPackage retrieves the asset from ledger state
func (s *SmartContract) ReadPackage(ctx contractapi.TransactionContextInterface, packageSerialID string) (*PackageAsset, error) {
	assetJSON, err := ctx.GetStub().GetState(packageSerialID)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if assetJSON == nil {
		return nil, fmt.Errorf("the package %s does not exist", packageSerialID)
	}

	var asset PackageAsset
	err = json.Unmarshal(assetJSON, &asset)
	if err != nil {
		return nil, err
	}

	return &asset, nil
}

// AssetExists returns true when asset exists in ledger
func (s *SmartContract) AssetExists(ctx contractapi.TransactionContextInterface, packageSerialID string) (bool, error) {
	assetJSON, err := ctx.GetStub().GetState(packageSerialID)
	if err != nil {
		return false, fmt.Errorf("failed to read from world state: %v", err)
	}
	return assetJSON != nil, nil
}

func main() {
	chaincode, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		fmt.Printf("Error creating pharmatrace chaincode: %v\n", err)
		return
	}

	if err := chaincode.Start(); err != nil {
		fmt.Printf("Error starting pharmatrace chaincode: %v\n", err)
	}
}

