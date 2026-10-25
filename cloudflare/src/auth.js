import { createRemoteJWKSet, jwtVerify } from "jose";

const appleKeys = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys"),
);
export const now = () => Math.floor(Date.now() / 1000);
export const randomToken = () =>
  Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
export async function hash(value) {
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(bytes), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
}
// Key resolver is injectable for cryptographic unit tests, never from HTTP or env.
export async function verifyAppleIdentity(
  token,
  nonceHash,
  audience,
  keys = appleKeys,
) {
  if (!audience || !/^[a-f0-9]{64}$/.test(nonceHash))
    throw new Error("invalid_auth");
  const { payload } = await jwtVerify(token, keys, {
    issuer: "https://appleid.apple.com",
    audience,
    algorithms: ["RS256"],
    requiredClaims: ["sub", "iat", "exp", "nonce"],
    maxTokenAge: "10 minutes",
  });
  if (payload.nonce !== nonceHash || !payload.sub || payload.sub.length > 255)
    throw new Error("invalid_auth");
  return payload.sub;
}
