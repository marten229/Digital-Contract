// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev Minimaler Reentrancy Guard (inspiriert von OpenZeppelin's ReentrancyGuard)
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    
    uint256 private _status;
    
    constructor() {
        _status = _NOT_ENTERED;
    }
    
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract ContractManager is ReentrancyGuard {
    enum ContractStatus { Created, Signed, Completed, Cancelled }

    struct ManagedContract {
        uint256 id;
        uint256 amount;
        address payable creator;       // Käufer
        address payable counterparty;  // Verkäufer
        ContractStatus status;
        string contractIPFSHash;
        bool deliveryRequired;
        bytes32 deliveryTrackingHash;
        bool deliveryConfirmed;
        bool deliveryApprovedByCreator;
    }

    mapping(uint256 => ManagedContract) public contracts;
    uint256 public contractCounter;

    mapping(address => uint256) public pendingWithdrawals;

    event ContractCreated(uint256 indexed contractId, address creator, address counterparty);
    event ContractSigned(uint256 indexed contractId);
    event PaymentReleased(uint256 indexed contractId, uint256 amount);
    event FundsWithdrawn(address indexed account, uint256 amount);
    event ContractDeactivated(uint256 indexed contractId);
    event TrackingHashSet(uint256 indexed contractId, bytes32 trackingHash);

    modifier onlyCreator(uint256 _contractId) {
        require(msg.sender == contracts[_contractId].creator, "Not creator");
        _;
    }

    modifier onlyCounterparty(uint256 _contractId) {
        require(msg.sender == contracts[_contractId].counterparty, "Not counterparty");
        _;
    }

    function createContract(
        address payable _counterparty,
        string memory _contractIPFSHash,
        uint256 _amount
    )
        public
        payable
    {
        require(_counterparty != address(0), "0 addr not allowed");
        require(msg.value == _amount, "ETH mismatch");

        contractCounter++;
        ManagedContract storage newContract = contracts[contractCounter];
        newContract.id = contractCounter;
        newContract.amount = _amount;
        newContract.creator = payable(msg.sender);
        newContract.counterparty = _counterparty;
        newContract.contractIPFSHash = _contractIPFSHash;
        newContract.status = ContractStatus.Created;

        emit ContractCreated(contractCounter, msg.sender, _counterparty);
    }

    function signContract(uint256 _contractId) public onlyCounterparty(_contractId) {
        ManagedContract storage mContract = contracts[_contractId];
        require(mContract.status == ContractStatus.Created, "Contract not in Created state");

        mContract.status = ContractStatus.Signed;
        emit ContractSigned(_contractId);
    }

    /// @notice Verkäufer (counterparty) setzt die Trackingnummer nach Signatur
    function setDeliveryTracking(uint256 _contractId, string memory _trackingNumber) public onlyCounterparty(_contractId) {
        ManagedContract storage mContract = contracts[_contractId];
        require(mContract.status == ContractStatus.Signed, "Contract must be Signed");
        require(!mContract.deliveryRequired, "Tracking already set");

        mContract.deliveryTrackingHash = keccak256(abi.encodePacked(_trackingNumber));
        mContract.deliveryRequired = true;

        emit TrackingHashSet(_contractId, mContract.deliveryTrackingHash);
    }

    /// @notice Oracle bestätigt erfolgreiche Zustellung durch DHL
    function confirmDeliveryByOracle(uint256 _contractId, string memory _trackingNumber) public nonReentrant {
        ManagedContract storage mContract = contracts[_contractId];
        require(mContract.deliveryRequired, "No delivery required");
        require(mContract.status == ContractStatus.Signed, "Contract not in Signed state");
        require(!mContract.deliveryConfirmed, "Already confirmed");

        require(
            mContract.deliveryTrackingHash == keccak256(abi.encodePacked(_trackingNumber)),
            "Tracking number mismatch"
        );

        mContract.deliveryConfirmed = true;
    }

    /// @notice Käufer (creator) bestätigt, dass der Paketinhalt korrekt ist
    function approveDeliveryAsCreator(uint256 _contractId) public onlyCreator(_contractId) {
        ManagedContract storage mContract = contracts[_contractId];
        require(mContract.deliveryRequired, "No delivery required");
        require(mContract.status == ContractStatus.Signed, "Contract not in Signed state");
        require(mContract.deliveryConfirmed, "Delivery not yet confirmed");
        require(!mContract.deliveryApprovedByCreator, "Already approved");

        mContract.deliveryApprovedByCreator = true;
        mContract.status = ContractStatus.Completed;
        pendingWithdrawals[mContract.counterparty] += mContract.amount;

        emit PaymentReleased(_contractId, mContract.amount);
    }

    /// @notice Nur für Verträge ohne Lieferung
    function confirmCompletion(uint256 _contractId) public nonReentrant onlyCreator(_contractId) {
        ManagedContract storage mContract = contracts[_contractId];
        require(mContract.status == ContractStatus.Signed, "Contract not signed");
        require(!mContract.deliveryRequired, "Use delivery flow");

        mContract.status = ContractStatus.Completed;
        pendingWithdrawals[mContract.counterparty] += mContract.amount;

        emit PaymentReleased(_contractId, mContract.amount);
    }

    function withdrawFunds() public nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds available");

        pendingWithdrawals[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");

        emit FundsWithdrawn(msg.sender, amount);
    }

    function deactivateContract(uint256 _contractId) public onlyCreator(_contractId) {
        ManagedContract storage mContract = contracts[_contractId];
        require(mContract.status != ContractStatus.Completed, "Cannot deactivate completed contract");
        require(mContract.status != ContractStatus.Cancelled, "Contract already deactivated");

        mContract.contractIPFSHash = "";
        mContract.status = ContractStatus.Cancelled;

        emit ContractDeactivated(_contractId);
    }

    function getContractStatus(uint256 _contractId) public view returns (ContractStatus) {
        return contracts[_contractId].status;
    }

    function getContractIPFSHash(uint256 _contractId) public view returns (string memory) {
        return contracts[_contractId].contractIPFSHash;
    }
}
