import json
import os
import sys
import time
import traceback
from typing import Dict, Any, Set

import requests
from dotenv import load_dotenv
from web3 import Web3

load_dotenv()

RPC_HTTP = os.getenv("RPC_HTTP")
CONTRACT_ADDRESS = os.getenv("CONTRACT_ADDRESS")
LEADER_ADDRESS = os.getenv("LEADER_ADDRESS")
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
POLL_SEC = int(os.getenv("POLL_SEC", "120"))

if not (CONTRACT_ADDRESS and LEADER_ADDRESS and SLACK_WEBHOOK_URL and RPC_HTTP):
    print("[error] Missing envs: CONTRACT_ADDRESS, LEADER_ADDRESS, SLACK_WEBHOOK_URL, RPC_HTTP")
    sys.exit(1)

ABI = [
  {"inputs":[{"internalType":"address","name":"leader","type":"address"}],"name":"leaderMessageIds","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"},
  {"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"messages","outputs":[
    {"internalType":"address","name":"sender","type":"address"},
    {"internalType":"address","name":"leader","type":"address"},
    {"internalType":"uint256","name":"amount","type":"uint256"},
    {"internalType":"uint64","name":"timestamp","type":"uint64"},
    {"internalType":"uint8","name":"status","type":"uint8"},
    {"internalType":"bytes32","name":"pubkeyUsed","type":"bytes32"},
    {"internalType":"bytes","name":"data","type":"bytes"}
  ],"stateMutability":"view","type":"function"}
]

STATE_PATH = os.getenv("STATE_PATH", "./watcher_state.json")

w3 = Web3(Web3.HTTPProvider(RPC_HTTP))
CONTRACT = w3.eth.contract(address=w3.to_checksum_address(CONTRACT_ADDRESS), abi=ABI)
LEADER = w3.to_checksum_address(LEADER_ADDRESS)


def load_state():
    try:
        with open(STATE_PATH, "r") as f:
            return json.load(f)
    except Exception:
        return {"seen_ids": []}

def save_state(seen: Set[int]):
    try:
        with open(STATE_PATH, "w") as f:
            json.dump({"seen_ids": sorted(list(seen))[-5000:]}, f)
    except Exception as e:
        print("[warn] failed to save state:", e)

state = load_state()
seen_ids: Set[int] = set(state.get("seen_ids", []))


def slack_post(text: str, blocks: Dict[str, Any] = None):
    payload = {"text": text}
    if blocks:
        payload["blocks"] = blocks
    r = requests.post(os.getenv("SLACK_WEBHOOK_URL"), json=payload, timeout=10)
    r.raise_for_status()


def format_amount(amount):
    return int(str(amount)) / 10**18


def notify_new_message(msg_id: int, sender: str,  amount: int, ts: int):
    ts_str = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(ts))
    text = (
        f"📨 New leadership inbox message #{msg_id}\n"
        f"• Time: {ts_str}\n"
        f"• From: {sender}\n"
        f"• Amount: {format_amount(amount)} ZK"
    )
    slack_post(text)


def poll_once():
    ids = CONTRACT.functions.leaderMessageIds(LEADER).call()
    new_ids = [int(i) for i in ids if int(i) not in seen_ids]
    if not new_ids:
        return 0
    
    print(f"[info] found {len(new_ids)} new message(s) for leader {LEADER}")

    new_ids.sort()
    for mid in new_ids:
        sender, leader, amount, timestamp, status, pubkeyUsed, data = CONTRACT.functions.messages(mid).call()
        if leader.lower() != LEADER.lower():
            continue
        notify_new_message(mid, sender, int(amount), int(timestamp))
        seen_ids.add(mid)
    save_state(seen_ids)
    return len(new_ids)


def main():
    while True:
        try:
            n = poll_once()
            if n:
                print(f"[ok] notified {n} new message(s)")
            time.sleep(POLL_SEC)
        except KeyboardInterrupt:
            print("bye"); break
        except Exception as e:
            print("[warn] poll error:", e)
            time.sleep(5)

if __name__ == '__main__':
    main()