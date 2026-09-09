// Spec 023 T002 — test vectors for passkey parsing and signing.
//
// Every key below was generated with `openssl genpkey` for these tests only
// and has never been registered anywhere. They are fixtures, not secrets.

/// PKCS#8, P-256 (COSE -7, ES256).
const es256PrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgsXPNUCtYJvj/t3pO
j0l+8lPDf+Hj3BOQG+G9CqFKr9+hRANCAASowUEpj6dRNu1qqBNMFeTTEN/dfNmD
mXl5Ff0wo+76ViV5+FstAJS7jCG7WJ5DnJcOKuzypVCKEhWwiJgycFXw
-----END PRIVATE KEY-----
''';

const es256PublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEqMFBKY+nUTbtaqgTTBXk0xDf3XzZ
g5l5eRX9MKPu+lYlefhbLQCUu4whu1ieQ5yXDirs8qVQihIVsIiYMnBV8A==
-----END PUBLIC KEY-----
''';

/// PKCS#8, Ed25519 (COSE -8, EdDSA).
const eddsaPrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIE/KNjFb/g7qelADCTqrUfJnMgM3wVBpkXgH6uT7QnUn
-----END PRIVATE KEY-----
''';

const eddsaPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAfvhLh0hetAAPqudMFN0ZkH6r6IFukCxUBJERIDY8dSc=
-----END PUBLIC KEY-----
''';

/// PKCS#8, RSA-2048 (COSE -257, RS256).
const rs256PrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCwsRJQhg8SR7ZI
h+74xB8Z2Mx5CollW5o6YKe1je3zV8qXviQuSOFq6VQPWOLPoft7biwOB911P/l/
4dtbHo2qT5un7SaZbnkGX6HWGKO2keX5DdzUIVKdo+06zi7iyQKmO+4ctPs9U3Kz
tGpDeopZcV/a9rvSK+cqMFy8xbnE0docEXkcy5SKbmYZiJUZeRTxOBNnlmOjUAK6
bJ12G+RHa2KrW8ryaUU1budjNSIQ2+6KjYP5QQlR0jDzHrT33B7Ua5XAyEoNwYAY
e0+/4zAZZgl3acMYXsXzgrHSS680P86IsJfXdCJLb4gZnzvlB09xYpLXhYjhLbwh
rwSoVoAdAgMBAAECggEAUb2RIfRq24OWdgaAzM/6LVxo96QivOO8PT6Cx5CB4N4f
6MQ7e7gWpH2N+E2gG/stWsQ0mEcWMgxnEby8XHKNihkrAuxIu5lqXsL2HRQoBKmJ
UQcTPoWt8SSpdld1RFBGq/20oc4uHohQ24be1BnIECnNdQBJEqlh11gpRuFYGA9R
C2z88vXZwS9w3QkWACzroHkHDtF/0M7DZli6dTqlap64HGU36SwmTpdhS4dMlOKg
kycNeNybVrd7AuusXTBRuTqgrjnB+aHqcafTvx6oGaxJJJQi6M03XnCGB1ojLyWz
nGQiVAmR/IoVQdEWrLv6LEiyLhuTMAAsOoR1ZO89xwKBgQDt0JKZqcUJ+axoomk6
B9VeMSrnzwNBbH9tUuj4D4taTlO3riyfbipd6U8tg2bZQ7mL7LPdZ+Q2cI/b0aRU
uL+j7vVu1iOd/s/uTUtTkwZi2E2EcmP2aK0+LcownPUF41QiGgk1m1FC8WeGj1xr
8mNqe3hvTf+PiPj8KMFMY9l4EwKBgQC+M/Z3UnoQ5miuR9WC2nXt/EmUlgyyQbPG
tdl4KwxisvzRu1381z4RWEs+7SvefDmhi4jl/CDO/BHBCr3pEKTiZyQWrBJiLDxX
ikL5ylRmit6Hp7rt8Tplm5zqTLAqCJSLkHxSwql0y62z1WpULoRxQjz8AFP/XlVI
D9sZFXKNDwKBgC9Ef37vUWyUJYJ+lW+lUvFv0FlWugzs5b7y9b8oR8hhPR6LDe96
VA1qbARd07lnTp/TIkTle2SeptlIJ+N2/RA2VK38/gNPPEDfOBOaa3CGEZI7skat
s5FiRIe5CrJq5rQIfMAc6N/nX25NXE9QVBY8CEoHNL5wuRxVdWYbioPlAoGAAcgu
2PNW3W2rMWbO40j0reQdNF0rhUgETSpK/Us59HrEz5o3yTSjCjqPieli7dSwHYlX
IQB5tja6W9qj6NkVEmHw/p1iFrVfY1qSQhDZNZS7fP3fTHdkGquYjsFlLR+jdKNH
5uaX+9YkrHilZGCDMSRzudCu+MeDeQddACEpT5UCgYEAlQ2oiEU9ow/i7cHqMXi9
spEktxPLLsJD3p4ZRsLGW9ofCASFAvbB7FqNjYFQXynsR6CUfov/bDCI0vUF32yW
6sxAAwWmkjl8tlK5AoN7NEw14s3vwfzWsp7OogM2jlH3zgSuIaKC8gYad2jKXIqd
S3j5FI3TDfF5Y0USOnDKs6c=
-----END PRIVATE KEY-----
''';

const rs256PublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsLESUIYPEke2SIfu+MQf
GdjMeQqJZVuaOmCntY3t81fKl74kLkjhaulUD1jiz6H7e24sDgfddT/5f+HbWx6N
qk+bp+0mmW55Bl+h1hijtpHl+Q3c1CFSnaPtOs4u4skCpjvuHLT7PVNys7RqQ3qK
WXFf2va70ivnKjBcvMW5xNHaHBF5HMuUim5mGYiVGXkU8TgTZ5Zjo1ACumyddhvk
R2tiq1vK8mlFNW7nYzUiENvuio2D+UEJUdIw8x6099we1GuVwMhKDcGAGHtPv+Mw
GWYJd2nDGF7F84Kx0kuvND/OiLCX13QiS2+IGZ875QdPcWKS14WI4S28Ia8EqFaA
HQIDAQAB
-----END PUBLIC KEY-----
''';

/// The ES256 PEM with its last base64 line dropped: parses as PEM, fails as
/// DER.
const truncatedPrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgsXPNUCtYJvj/t3pO
-----END PRIVATE KEY-----
''';

/// `authenticatorData` for rpId `webauthn.io`, flags UP|UV|BE|BS (0x1D),
/// sign count 0 — see `data-model.md`.
const webauthnIoRpId = 'webauthn.io';
const webauthnIoRpIdHashHex =
    '74a6ea9213c99c2f74b22492b320cf40262a94c1a950a0397f29250b60841ef0';
const webauthnIoAuthenticatorDataHex = '${webauthnIoRpIdHashHex}1d00000000';
