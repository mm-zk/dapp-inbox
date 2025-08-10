// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Leadership Inbox — encrypted pay-to-prioritize messaging
/// @notice MVP contract for registering leadership encryption keys and storing encrypted messages.
contract LeadershipInbox {
    // ===== Reentrancy Guard (minimal, no OZ dep) =====
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    modifier nonReentrant() {
        require(_status != _ENTERED, "REENTRANCY");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    constructor() { _status = _NOT_ENTERED; }

    // ===== ERC20 safe call helpers =====
    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value)); // transferFrom
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }
    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value)); // transfer
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    // ===== Data =====
    enum Status { New, Read, Completed }

    struct Msg {
        address sender;
        address leader;
        address token;
        uint256 amount;
        uint64  timestamp;
        Status  status;
        bytes32 pubkeyUsed; // which registered key was used to encrypt
        bytes   data;       // [ephemeralPK(32) | nonce(24) | ciphertext]
    }

    struct Leader {
        bool isLeader;
        bytes32 activeKey;
        mapping(bytes32 => bool) allowed; // active + legacy keys allowed for incoming messages
        bytes32[] keys; // historical list (some may be disabled)
    }

    mapping(address => Leader) private leaderInfo;

    Msg[] public messages; // auto-getter returns the struct fields

    mapping(address => uint256[]) private leaderToMsgIds;
    mapping(address => uint256[]) private senderToMsgIds;

    // escrow balances: leader => token => amount
    mapping(address => mapping(address => uint256)) public balances;

    // ===== Events =====
    event LeaderRegistered(address indexed leader, bytes32 pubKey);
    event ActiveKeySet(address indexed leader, bytes32 pubKey);
    event LegacyKeySet(address indexed leader, bytes32 pubKey, bool allowed);
    event MessageSent(uint256 indexed id, address indexed leader, address indexed sender, address token, uint256 amount);
    event MessageStatusChanged(uint256 indexed id, Status status);
    event Withdrawal(address indexed leader, address indexed token, address to, uint256 amount);

    // ===== Modifiers =====
    modifier onlyLeader() { require(leaderInfo[msg.sender].isLeader, "NOT_LEADER"); _; }
    modifier onlyLeaderOf(uint256 id) { require(id < messages.length, "BAD_ID"); require(messages[id].leader == msg.sender, "NOT_OWNER"); _; }

    // ===== Leader management =====
    function registerLeader(bytes32 pubKey) external {
        require(pubKey != bytes32(0), "BAD_KEY");
        Leader storage L = leaderInfo[msg.sender];
        if (!L.isLeader) {
            L.isLeader = true;
        }
        if (!L.allowed[pubKey]) {
            L.allowed[pubKey] = true;
            L.keys.push(pubKey);
        }
        L.activeKey = pubKey;
        emit LeaderRegistered(msg.sender, pubKey);
        emit ActiveKeySet(msg.sender, pubKey);
    }

    function setActiveKey(bytes32 pubKey) external onlyLeader {
        Leader storage L = leaderInfo[msg.sender];
        if (!L.allowed[pubKey]) {
            L.allowed[pubKey] = true;
            L.keys.push(pubKey);
        }
        L.activeKey = pubKey;
        emit ActiveKeySet(msg.sender, pubKey);
    }

    function addLegacyKey(bytes32 pubKey) external onlyLeader {
        Leader storage L = leaderInfo[msg.sender];
        if (!L.allowed[pubKey]) {
            L.allowed[pubKey] = true;
            L.keys.push(pubKey);
        }
        emit LegacyKeySet(msg.sender, pubKey, true);
    }

    function removeLegacyKey(bytes32 pubKey) external onlyLeader {
        Leader storage L = leaderInfo[msg.sender];
        require(L.allowed[pubKey], "NOT_FOUND");
        L.allowed[pubKey] = false;
        if (L.activeKey == pubKey) {
            L.activeKey = bytes32(0);
        }
        emit LegacyKeySet(msg.sender, pubKey, false);
    }

    function getLeader(address who) external view returns (bool isLeader_, bytes32 activeKey_) {
        Leader storage L = leaderInfo[who];
        return (L.isLeader, L.activeKey);
    }

    function getLeaderKeys(address who) external view returns (bytes32[] memory keys, bool[] memory allowed) {
        Leader storage L = leaderInfo[who];
        keys = L.keys;
        allowed = new bool[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            allowed[i] = L.allowed[keys[i]];
        }
    }

    function isKeyAllowed(address who, bytes32 key) external view returns (bool) {
        return leaderInfo[who].allowed[key];
    }

    // ===== Messaging =====
    function sendMessage(
        address leader,
        address token,
        uint256 amount,
        bytes32 pubkeyUsed,
        bytes calldata ciphertext
    ) external nonReentrant returns (uint256 id) {
        Leader storage L = leaderInfo[leader];
        require(L.isLeader, "NO_SUCH_LEADER");
        require(L.allowed[pubkeyUsed], "KEY_NOT_ALLOWED");

        if (amount > 0) {
            require(token != address(0), "TOKEN_REQ");
            _safeTransferFrom(token, msg.sender, address(this), amount);
            balances[leader][token] += amount;
        }

        Msg memory m = Msg({
            sender: msg.sender,
            leader: leader,
            token: token,
            amount: amount,
            timestamp: uint64(block.timestamp),
            status: Status.New,
            pubkeyUsed: pubkeyUsed,
            data: ciphertext
        });

        messages.push(m);
        id = messages.length - 1;
        leaderToMsgIds[leader].push(id);
        senderToMsgIds[msg.sender].push(id);
        emit MessageSent(id, leader, msg.sender, token, amount);
    }

    function markAsRead(uint256 id) external onlyLeaderOf(id) {
        Msg storage m = messages[id];
        require(m.status == Status.New, "ALREADY_READ");
        m.status = Status.Read;
        emit MessageStatusChanged(id, Status.Read);
    }

    function markAsCompleted(uint256 id) external onlyLeaderOf(id) {
        Msg storage m = messages[id];
        m.status = Status.Completed;
        emit MessageStatusChanged(id, Status.Completed);
    }

    // ===== Views for pagination =====
    function leaderMessageIds(address leader) external view returns (uint256[] memory) {
        return leaderToMsgIds[leader];
    }
    function senderMessageIds(address sender) external view returns (uint256[] memory) {
        return senderToMsgIds[sender];
    }

    // ===== Withdrawals =====
    function withdraw(address token, address to, uint256 amount) external onlyLeader nonReentrant {
        require(to != address(0), "BAD_TO");
        uint256 bal = balances[msg.sender][token];
        require(amount <= bal, "INSUFFICIENT");
        balances[msg.sender][token] = bal - amount;
        _safeTransfer(token, to, amount);
        emit Withdrawal(msg.sender, token, to, amount);
    }

    function version() external pure returns (string memory) { return "1.0.0"; }
}