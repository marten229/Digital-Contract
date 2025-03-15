// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Minimal reentrancy guard (inspired by OpenZeppelin's ReentrancyGuard)
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

contract DigitalContractPlatform is ReentrancyGuard {
    enum ContractStatus { Created, Signed, Completed, Cancelled }

    struct Contract {
        uint256 id;
        address payable creator;
        address payable counterparty;
        string contractIPFSHash;
        uint256 amount;
        ContractStatus status;
    }

    mapping(uint256 => Contract) public contracts;
    uint256 public contractCounter;

    // Mapping for funds that the counterparty can withdraw.
    mapping(address => uint256) public pendingWithdrawals;

    event ContractCreated(uint256 indexed contractId, address creator, address counterparty);
    event ContractSigned(uint256 indexed contractId);
    event PaymentReleased(uint256 indexed contractId, uint256 amount);

    /// @notice Create a new contract. The creator must send the exact amount.
    function createContract(
        address payable _counterparty, 
        string memory _contractIPFSHash, 
        uint256 _amount
    ) 
        public 
        payable 
    {
        require(msg.value == _amount, "Sent ether must match the contract amount");

        contractCounter++;
        contracts[contractCounter] = Contract({
            id: contractCounter,
            creator: payable(msg.sender),
            counterparty: _counterparty,
            contractIPFSHash: _contractIPFSHash,
            amount: _amount,
            status: ContractStatus.Created
        });

        emit ContractCreated(contractCounter, msg.sender, _counterparty);
    }

    /// @notice The designated counterparty signs the contract.
    function signContract(uint256 _contractId) public {
        Contract storage digitalContract = contracts[_contractId];

        require(msg.sender == digitalContract.counterparty, "Only counterparty can sign");
        require(digitalContract.status == ContractStatus.Created, "Contract must be in 'Created' status");

        digitalContract.status = ContractStatus.Signed;
        emit ContractSigned(_contractId);
    }

    /// @notice The creator confirms contract completion. Instead of immediately transferring funds,
    /// the amount is recorded for withdrawal by the counterparty.
    function confirmCompletion(uint256 _contractId) public nonReentrant {
        Contract storage digitalContract = contracts[_contractId];

        require(msg.sender == digitalContract.creator, "Only creator can confirm completion");
        require(digitalContract.status == ContractStatus.Signed, "Contract must be signed");

        digitalContract.status = ContractStatus.Completed;
        pendingWithdrawals[digitalContract.counterparty] += digitalContract.amount;
        emit PaymentReleased(_contractId, digitalContract.amount);
    }

    /// @notice Allows users to withdraw funds owed to them.
    function withdrawFunds() public nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw");

        pendingWithdrawals[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");
    }

    /// @notice Retrieve the current status of a contract.
    function getContractStatus(uint256 _contractId) public view returns (ContractStatus) {
        return contracts[_contractId].status;
    }

    /// @notice Retrieve the IPFS hash associated with a contract.
    function getContractIPFSHash(uint256 _contractId) public view returns (string memory) {
        return contracts[_contractId].contractIPFSHash;
    }
}
