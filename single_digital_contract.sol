// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ContractInstance is ReentrancyGuard {
    enum ContractStatus {
        Created,
        Signed,
        DeliverySet,
        DeliveryConfirmed,
        DeliveryApproved,
        AgreementFulfilled,
        Completed,
        Cancelled
    }

    address payable public creator;
    address payable public counterparty;
    address public oracle;
    bool public oracleSet;

    uint256 public amount;
    ContractStatus public status;
    bytes32 public contractHash;
    bytes32 public deliveryTrackingHash;
    bool public deliveryRequired;
    bool public withdrawn;

    event ContractCreated(address indexed creator, address indexed counterparty);
    event ContractSigned();
    event TrackingHashSet(bytes32 trackingHash);
    event DeliveryConfirmed();
    event DeliveryApproved();
    event PaymentReleased(address indexed to, uint256 amount);
    event FundsWithdrawn(address indexed account, uint256 amount);
    event ContractDeactivated();
    event OracleSet(address indexed oracle);

    modifier onlyCreator() {
        require(msg.sender == creator, "Not creator");
        _;
    }

    modifier onlyCounterparty() {
        require(msg.sender == counterparty, "Not counterparty");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle, "Not oracle");
        _;
    }

    constructor(
        address payable _counterparty,
        bytes32 _contractHash
    ) payable {
        require(_counterparty != address(0), "0 addr not allowed");
        require(msg.value > 0, "ETH required");

        creator = payable(msg.sender);
        counterparty = _counterparty;
        amount = msg.value;
        contractHash = _contractHash;
        status = ContractStatus.Created;

        emit ContractCreated(creator, counterparty);
    }

    function setOracle(address _oracle) public onlyCreator {
        require(!oracleSet, "Oracle already set");
        require(_oracle != address(0), "Invalid oracle");

        oracle = _oracle;
        oracleSet = true;
        emit OracleSet(_oracle);
    }

    function signContract() public onlyCounterparty {
        require(status == ContractStatus.Created, "Not Created");
        status = ContractStatus.Signed;
        emit ContractSigned();
    }

    function setDeliveryTracking(bytes32 _trackingNumberHash) public onlyCounterparty {
        require(status == ContractStatus.Signed, "Not Signed");
        require(!deliveryRequired, "Already set");

        deliveryTrackingHash = _trackingNumberHash;
        deliveryRequired = true;
        status = ContractStatus.DeliverySet;

        emit TrackingHashSet(_trackingNumberHash);
    }

    function confirmDeliveryByOracle(bytes32 _trackingNumberHash) public onlyOracle {
        require(status == ContractStatus.DeliverySet, "Wrong status");
        require(deliveryRequired, "No delivery");
        require(deliveryTrackingHash == _trackingNumberHash, "Hash mismatch");

        status = ContractStatus.DeliveryConfirmed;
        emit DeliveryConfirmed();
    }

    function approveDeliveryAsCreator() public onlyCreator {
        require(status == ContractStatus.DeliveryConfirmed, "Wrong status");

        status = ContractStatus.DeliveryApproved;
        emit DeliveryApproved();
        emit PaymentReleased(counterparty, amount);
    }

    function confirmCompletion() public onlyCreator {
        require(status == ContractStatus.Signed, "Not signed");
        require(!deliveryRequired, "Delivery flow required");

        status = ContractStatus.AgreementFulfilled;
        emit PaymentReleased(counterparty, amount);
    }

    function withdrawFunds() public nonReentrant onlyCounterparty {
        require(
            status == ContractStatus.AgreementFulfilled ||
            status == ContractStatus.DeliveryApproved,
            "Not withdrawable"
        );
        require(!withdrawn, "Already withdrawn");

        withdrawn = true;
        status = ContractStatus.Completed;

        counterparty.transfer(amount);
        emit FundsWithdrawn(counterparty, amount);
    }

    function deactivateContract() public onlyCreator {
        require(status == ContractStatus.Completed, "Only Completed");

        delete contractHash;
        delete deliveryTrackingHash;
        status = ContractStatus.Cancelled;

        emit ContractDeactivated();
    }

    function getContractStatus() public view returns (ContractStatus) {
        return status;
    }
}
