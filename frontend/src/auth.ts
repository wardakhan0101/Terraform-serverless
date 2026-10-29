import { AuthenticationDetails, CognitoUser, CognitoUserAttribute, CognitoUserPool, type CognitoUserSession } from 'amazon-cognito-identity-js';
import type { Config, Role } from './api';

// Credentials/tokens live in memory only. Reloading the page signs the user out.
const values = new Map<string, string>();
const storage = { setItem: (k: string, v: string) => { values.set(k, v); return v; },
  getItem: (k: string) => values.get(k) ?? null, removeItem: (k: string) => { values.delete(k); }, clear: () => values.clear() };

function pool(config: Config, role: Role) {
  return new CognitoUserPool({ UserPoolId: config.pools[role].poolId, ClientId: config.pools[role].clientId, Storage: storage });
}
function user(config: Config, role: Role, email: string) {
  return new CognitoUser({ Username: email, Pool: pool(config, role), Storage: storage });
}
export async function signUp(config: Config, role: Role, email: string, password: string) {
  return new Promise<void>((resolve, reject) => pool(config, role).signUp(email, password,
    [new CognitoUserAttribute({ Name: 'email', Value: email })], [], error => error ? reject(error) : resolve()));
}
export async function confirm(config: Config, role: Role, email: string, code: string) {
  return new Promise<void>((resolve, reject) => user(config, role, email).confirmRegistration(code, true,
    error => error ? reject(error) : resolve()));
}
export async function signIn(config: Config, role: Role, email: string, password: string) {
  const current = user(config, role, email);
  await new Promise<CognitoUserSession>((resolve, reject) => current.authenticateUser(
    new AuthenticationDetails({ Username: email, Password: password }),
    { onSuccess: resolve, onFailure: reject,
      totpRequired: () => reject(new Error('This account requires an authenticator code. Use the MFA sign-in option.')) }));
  return current;
}
export function getToken(current: CognitoUser): Promise<string> {
  return new Promise((resolve, reject) => current.getSession((error: Error | null, session: CognitoUserSession | null) => {
    if (error || !session?.isValid()) reject(error || new Error('Please sign in again.'));
    else resolve(session.getIdToken().getJwtToken());
  }));
}
