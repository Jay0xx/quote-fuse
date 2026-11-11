# Quote Fuse frontend

Wallet-free Overview and Stage 3 Replay, built with Vite and TypeScript. The replay imports the verified `deployments/stage-3-replay.json` fixture from the repository root. The exported contract ABIs in `abi/` are available for a later Live State pass.

```sh
cd frontend
npm install
npm run dev
```

Open the printed local URL. `npm run build` type-checks and creates `frontend/dist/`.

The stale result is historical `eth_call` evidence and is labeled “Simulated against the live contract.” The `10.43 s` timing describes one recorded run with 1-second polling, independent of replay speed.
