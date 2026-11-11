import fixture from "../../deployments/stage-3-replay.json";
import "./style.css";

type Route = "overview" | "replay";
type Chain = "unichain" | "lasna" | "base";

const $ = <T extends HTMLElement = HTMLElement>(id: string): T => {
  const element = document.getElementById(id);
  if (!element) throw new Error(`Missing frontend element: ${id}`);
  return element as T;
};

const shortened = (hash: string) => `${hash.slice(0, 8)}…${hash.slice(-6)}`;
const formatToken = (raw: string, digits = 4) => {
  const divisor = 10n ** BigInt(18 - digits);
  const rounded = (BigInt(raw) + divisor / 2n) / divisor;
  const displayScale = 10n ** BigInt(digits);
  const whole = rounded / displayScale;
  const fractional = (rounded % displayScale).toString().padStart(digits, "0");
  return `${whole}.${fractional}`;
};
const link = (url: string, label: string) => {
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.target = "_blank";
  anchor.rel = "noopener noreferrer";
  anchor.textContent = `${label} ↗`;
  return anchor;
};
const setDetail = (
  element: HTMLElement,
  text: string,
  url?: string,
  label?: string,
) => {
  element.replaceChildren(document.createTextNode(text));
  if (url && label) {
    element.append(document.createElement("br"), link(url, label));
  }
};

const transaction = fixture.linkedTransactions;
const outcome = fixture.settlementOutcomes;
const move = fixture.priceMove;
const control = fixture.quotes.controlInitial;
const protectedQuote = fixture.quotes.protectedInitial;
const fresh = fixture.quotes.protectedFresh;
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

// The landing diagram has one short signal pass, then holds the result.
function initHero() {
  const terms = `${formatToken(control.terms.makerAmount)} QSA for ${formatToken(control.terms.takerAmount)} QSB`;
  document.querySelectorAll(".hero-slip .slip-main p").forEach((element) => {
    element.textContent = terms;
  });
  const visual = $("hero-visual");
  const marker = document.getElementById(
    "hero-marker",
  ) as unknown as SVGCircleElement;
  const path = document.getElementById(
    "hero-signal-path",
  ) as unknown as SVGPathElement;
  let frame = 0;
  let timeout = 0;
  const finish = () => {
    cancelAnimationFrame(frame);
    window.clearTimeout(timeout);
    visual.classList.add("is-final");
    $("hero-version").textContent = `v${fixture.versions.appliedVersion}`;
    $("hero-protected-status").textContent = "Stale";
    $("hero-gate-text").textContent = "open";
    $("hero-caption").textContent =
      "Callback applied. The protected path is open.";
  };
  if (reducedMotion.matches) {
    finish();
    return;
  }
  timeout = window.setTimeout(() => {
    const length = path.getTotalLength();
    const start = performance.now();
    const duration = 2200;
    const advance = (time: number) => {
      const progress = Math.min(1, (time - start) / duration);
      const point = path.getPointAtLength(length * progress);
      marker.setAttribute("cx", String(point.x));
      marker.setAttribute("cy", String(point.y));
      (path as SVGPathElement).style.strokeDashoffset = String(
        length * (1 - progress),
      );
      if (progress < 1) frame = requestAnimationFrame(advance);
      else finish();
    };
    frame = requestAnimationFrame(advance);
  }, 480);
  reducedMotion.addEventListener(
    "change",
    () => {
      if (reducedMotion.matches) finish();
    },
    { once: true },
  );
}

function routeFromHash(): Route {
  return location.hash === "#replay" ? "replay" : "overview";
}
function renderRoute() {
  const route = routeFromHash();
  $("overview").hidden = route !== "overview";
  $("replay").hidden = route !== "replay";
  document
    .querySelectorAll<HTMLAnchorElement>("[data-route]")
    .forEach((anchor) => {
      if (anchor.dataset.route === route)
        anchor.setAttribute("aria-current", "page");
      else anchor.removeAttribute("aria-current");
    });
  document.title =
    route === "overview"
      ? "Quote Fuse — Invalidate stale quotes"
      : "Quote Fuse — Replay the testnet run";
  window.scrollTo({ top: 0, behavior: "instant" });
}

const steps = [
  "Starting quotes",
  "Unichain swap",
  "Lasna reaction",
  "Base callback",
  "Control fill",
  "Fresh v1 fill",
];
let step = 0;
let selectedChain: Chain = "unichain";
let timer: number | undefined;

function stopPlayback() {
  if (timer !== undefined) window.clearTimeout(timer);
  timer = undefined;
  $("play-button").toggleAttribute("disabled", false);
  $("pause-button").toggleAttribute("disabled", true);
}
function showStep(next: number) {
  step = Math.max(0, Math.min(5, next));
  $("transport-count").textContent = `${String(step).padStart(2, "0")} / 05`;
  document
    .querySelectorAll<HTMLButtonElement>("[data-step]")
    .forEach((button) => {
      const value = Number(button.dataset.step);
      button.classList.toggle("is-complete", value < step);
      if (value === step) button.setAttribute("aria-current", "step");
      else button.removeAttribute("aria-current");
    });
  const status = [
    "Two matching v0 quotes are fillable before the swap.",
    `Unichain pool price moves ${move.delta.moveBpsApprox.toFixed(2)} bps, passing the ${move.thresholdBps} bps threshold.`,
    "Lasna accepts the pool event and requests a Base callback for v1.",
    "Base applies v1. The protected v0 quote is now stale before expiry.",
    "The control v0 quote fills after the same price move.",
    "A repriced protected v1 quote fills with a fresh nonce.",
  ];
  $("replay-status-text").textContent = status[step];
  $("move-value").textContent =
    step >= 1 ? `${move.delta.moveBpsApprox.toFixed(2)} bps` : "0 bps";
  $("price-after").textContent =
    step >= 1 ? formatToken(move.postSwap.newPrice, 6) : "—";
  $("meter-fill").style.width =
    step >= 1
      ? `${Math.min(100, (move.delta.moveBpsApprox / 400) * 100)}%`
      : "0%";
  $("meter-note").textContent =
    step >= 1
      ? `${move.qualifyingSwap.amountInFormatted} → ${move.qualifyingSwap.amountOutFormatted}. The new price is ${formatToken(move.postSwap.newPrice, 6)} QFB/QFA.`
      : "A 20 QFA swap updates the pool reserves. Replay to see the move.";
  $("replay-version").textContent =
    step >= 3
      ? `v${fixture.versions.appliedVersion}`
      : `v${fixture.versions.initialVersion}`;
  $("switch-display").classList.toggle("is-open", step >= 3);
  $("switch-label").textContent =
    step >= 3
      ? "Circuit open · old quote stale"
      : "Circuit closed · quote fillable";
  const revealed = { unichain: step >= 1, lasna: step >= 2, base: step >= 3 };
  (Object.keys(revealed) as Chain[]).forEach((chain) => {
    const node = $(`node-${chain}`);
    node.textContent = revealed[chain]
      ? "Receipt confirmed"
      : `Awaiting ${chain === "unichain" ? "swap" : chain === "lasna" ? "reaction" : "callback"}`;
    node
      .closest(".chain-node")
      ?.classList.toggle("is-revealed", revealed[chain]);
  });
  $("result-control").classList.toggle("is-confirmed", step >= 4);
  $("control-result-pill").textContent = step >= 4 ? "Filled" : "Ready";
  setDetail(
    $("control-result-detail"),
    step >= 4
      ? `Base receipt · ${shortened(outcome.controlFillReceipt.transactionHash)}`
      : "Waiting for the recorded fill",
    step >= 4 ? outcome.controlFillReceipt.explorerUrl : undefined,
    step >= 4 ? "Open fill receipt" : undefined,
  );
  $("result-protected").classList.toggle("is-stale", step >= 3);
  $("protected-result-pill").textContent = step >= 3 ? "Stale" : "Ready";
  const staleDetail = $("protected-result-detail");
  if (step >= 3) {
    staleDetail.replaceChildren();
    const label = document.createElement("span");
    label.className = "stale-label";
    label.textContent = "Simulated against the live contract.";
    staleDetail.append(
      label,
      document.createTextNode(
        `${outcome.staleProtectedQuoteRejection.decodedError.formatted} · nonce 1 unused`,
      ),
    );
  } else staleDetail.textContent = "Waiting for the authenticated callback";
  $("result-fresh").classList.toggle("is-confirmed", step >= 5);
  $("fresh-result-pill").textContent = step >= 5 ? "Filled" : "Pending";
  setDetail(
    $("fresh-result-detail"),
    step >= 5
      ? `Base receipt · ${shortened(outcome.freshProtectedFillReceipt.transactionHash)}`
      : "Waiting for the fresh fill",
    step >= 5 ? outcome.freshProtectedFillReceipt.explorerUrl : undefined,
    step >= 5 ? "Open fresh fill receipt" : undefined,
  );
  renderEvidence();
}

function renderEvidence() {
  document
    .querySelectorAll<HTMLButtonElement>("[data-chain]")
    .forEach((button) =>
      button.setAttribute(
        "aria-pressed",
        String(button.dataset.chain === selectedChain),
      ),
    );
  const evidence = $("evidence");
  const stage = { unichain: 1, lasna: 2, base: 3 }[selectedChain];
  if (step < stage) {
    evidence.innerHTML = `<span class="evidence-pending">${{ unichain: "Unichain swap", lasna: "Lasna reaction", base: "Base callback" }[selectedChain]} evidence appears at step ${stage}. Select a step or press Play.</span>`;
    return;
  }
  const tx =
    selectedChain === "unichain"
      ? transaction.unichainQualifyingSwap
      : selectedChain === "lasna"
        ? transaction.lasnaReaction
        : transaction.baseVersionAdvance;
  const titles = {
    unichain: "Pool Sync · price changed",
    lasna: "ReferenceAccepted · callback requested",
    base: "VersionAdvanced · v0 → v1",
  };
  const event =
    selectedChain === "unichain"
      ? `Sync reserves: ${transaction.unichainQualifyingSwap.emittedSync.reserve0} / ${transaction.unichainQualifyingSwap.emittedSync.reserve1}`
      : selectedChain === "lasna"
        ? `Accepted reference ${formatToken(transaction.lasnaReaction.emittedReferenceAccepted.newPrice, 6)} QFB/QFA; requested v${transaction.lasnaReaction.emittedReferenceAccepted.version}`
        : `Authenticated Base callback advanced protected settlement to v${transaction.baseVersionAdvance.emittedVersionAdvanced.newVersion}`;
  evidence.replaceChildren();
  const title = document.createElement("strong");
  title.className = "evidence-title";
  title.textContent = titles[selectedChain];
  const meta = document.createElement("span");
  meta.className = "evidence-meta";
  meta.textContent = `Block ${tx.blockNumber.toLocaleString()} · ${tx.gasUsed.toLocaleString()} gas · ${shortened(tx.transactionHash)}`;
  const detail = document.createElement("span");
  detail.className = "evidence-event";
  detail.textContent = event;
  const anchor = link(tx.explorerUrl, "View transaction");
  anchor.className = "evidence-link";
  evidence.append(title, meta, detail, anchor);
}

function play() {
  if (reducedMotion.matches) {
    stopPlayback();
    showStep(5);
    return;
  }
  if (step >= 5) showStep(0);
  if (timer !== undefined) return;
  $("play-button").toggleAttribute("disabled", true);
  $("pause-button").toggleAttribute("disabled", false);
  const advance = () => {
    if (step >= 5) {
      stopPlayback();
      return;
    }
    showStep(step + 1);
    timer = window.setTimeout(advance, 1150);
  };
  timer = window.setTimeout(advance, 420);
}

function initReplay() {
  $("price-before").textContent = formatToken(
    move.preSwap.acceptedReference,
    6,
  );
  $("price-after").textContent = formatToken(move.postSwap.newPrice, 6);
  $("observed-time").textContent =
    `${transaction.timingObservation.observedIntervalSeconds.toFixed(2)} s observed`;
  const track = $("step-track");
  steps.forEach((name, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.step = String(index);
    const number = document.createElement("span");
    number.textContent = String(index).padStart(2, "0");
    button.append(number, document.createTextNode(name));
    button.addEventListener("click", () => {
      stopPlayback();
      showStep(index);
    });
    track.append(button);
  });
  document
    .querySelectorAll<HTMLButtonElement>("[data-chain]")
    .forEach((button) =>
      button.addEventListener("click", () => {
        selectedChain = button.dataset.chain as Chain;
        renderEvidence();
      }),
    );
  $("play-button").addEventListener("click", play);
  $("pause-button").addEventListener("click", stopPlayback);
  $("step-button").addEventListener("click", () => {
    stopPlayback();
    showStep(Math.min(5, step + 1));
  });
  $("reset-button").addEventListener("click", () => {
    stopPlayback();
    selectedChain = "unichain";
    showStep(0);
  });
  stopPlayback();
  showStep(0);
}

window.addEventListener("hashchange", renderRoute);
initHero();
initReplay();
renderRoute();
