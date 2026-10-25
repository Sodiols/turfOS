"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import { browserDatabase } from "@/lib/browser-supabase";

export function MfaSetup() {
  const router = useRouter();
  const [qr, setQr] = useState("");
  const [factor, setFactor] = useState("");
  const [code, setCode] = useState("");
  const [error, setError] = useState("");
  const [pending, setPending] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    browserDatabase().auth.mfa.listFactors().then(({ data, error }) => {
      if (!active) return;
      if (error) setError(error.message);
      else setFactor(data.totp.find((item) => item.status === "verified")?.id ?? "");
      setLoading(false);
    });
    return () => { active = false; };
  }, []);

  async function enroll() {
    setPending(true);
    setError("");
    const { data, error } = await browserDatabase().auth.mfa.enroll({ factorType: "totp", friendlyName: "TurfOS platform admin" });
    if (error) setError(error.message);
    else { setQr(data.totp.qr_code); setFactor(data.id); }
    setPending(false);
  }

  async function verify() {
    setPending(true);
    setError("");
    const db = browserDatabase();
    const challenge = await db.auth.mfa.challenge({ factorId: factor });
    if (challenge.error) { setError(challenge.error.message); setPending(false); return; }
    const result = await db.auth.mfa.verify({ factorId: factor, challengeId: challenge.data.id, code });
    if (result.error) setError(result.error.message);
    else router.push("/platform-admin/overview");
    setPending(false);
  }

  return <div className="mfa-setup">
    {loading ? <p>Checking authenticators…</p> : !factor && <button className="button" type="button" onClick={enroll} disabled={pending}>Set up authenticator</button>}
    {qr && <><p>Scan with your authenticator app, then enter its six-digit code.</p><Image src={qr} alt="Authenticator setup QR code" width={220} height={220} unoptimized /></>}
    {factor && <><label className="field">Authentication code<input inputMode="numeric" autoComplete="one-time-code" value={code} onChange={(event) => setCode(event.target.value)} maxLength={6} /></label><button className="button primary" type="button" onClick={verify} disabled={pending || code.length !== 6}>Verify and continue</button></>}
    {error && <p role="alert" className="notice danger">{error}</p>}
  </div>;
}
