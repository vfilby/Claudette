# Release setup — signing & notarization secrets

The [`Release`](workflows/release.yml) workflow does **all** signing and
notarization in the pipeline — nothing is signed on a developer's Mac. You only
need to provide the credentials once, as GitHub Actions repository secrets.

There are two credentials Apple requires:

1. A **Developer ID Application** certificate (+ its private key) — to *sign* the app.
2. An **App Store Connect API key** — to *notarize* it with Apple.

Both require membership in the [Apple Developer Program](https://developer.apple.com/programs/)
($99/yr). Once you have them, releasing is just `git push origin v0.2.0`.

---

## 1. Developer ID Application certificate → `.p12`

1. In **Xcode → Settings → Accounts**, add your Apple ID, select your team,
   click **Manage Certificates… → + → Developer ID Application**.
   (Or create one at <https://developer.apple.com/account/resources/certificates>.)
2. Open **Keychain Access**, find the *Developer ID Application: …* certificate,
   expand it so the private key is included, right-click → **Export 2 items…**,
   save as `Certificates.p12`, and set an export password. Remember it.
3. Base64-encode it for the secret:
   ```sh
   base64 -i Certificates.p12 | pbcopy   # now on your clipboard
   ```

Secrets to add:
- **`BUILD_CERTIFICATE_BASE64`** ← the base64 string from step 3.
- **`P12_PASSWORD`** ← the export password you set in step 2.
- **`KEYCHAIN_PASSWORD`** ← any random string (used only for the throwaway CI keychain).
- **`APPLE_TEAM_ID`** ← your 10-character Team ID (find it at
  <https://developer.apple.com/account> → Membership, or it's the `(XXXXXXXXXX)`
  suffix in the certificate name).

## 2. App Store Connect API key → `.p8`

1. Go to <https://appstoreconnect.apple.com/access/integrations/api>
   (**Users and Access → Integrations → App Store Connect API**).
2. Create a key with the **Developer** role (sufficient for notarization).
3. Download the `AuthKey_XXXXXXXXXX.p8` — **you can only download it once.**
4. Note the **Key ID** (on the key row) and the **Issuer ID** (top of the page).
5. Base64-encode the key:
   ```sh
   base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
   ```

Secrets to add:
- **`AC_API_KEY_BASE64`** ← the base64 string from step 5.
- **`AC_API_KEY_ID`** ← the Key ID.
- **`AC_API_ISSUER_ID`** ← the Issuer ID.

---

## 3. Add the secrets to the repo

Either via the GitHub UI (**Settings → Secrets and variables → Actions →
New repository secret**) or with the `gh` CLI:

```sh
gh secret set BUILD_CERTIFICATE_BASE64 < <(base64 -i Certificates.p12)
gh secret set P12_PASSWORD
gh secret set KEYCHAIN_PASSWORD
gh secret set APPLE_TEAM_ID
gh secret set AC_API_KEY_BASE64 < <(base64 -i AuthKey_XXXXXXXXXX.p8)
gh secret set AC_API_KEY_ID
gh secret set AC_API_ISSUER_ID
```

(`gh secret set NAME` with no value prompts you to paste/type it — nothing is echoed.)

## 4. Cut a release

```sh
git tag v0.2.0
git push origin v0.2.0
```

The workflow builds, signs, notarizes, staples, packages a `.zip` and `.dmg`,
and publishes them to a GitHub Release. You can also run it manually from the
**Actions** tab (provide the tag) once the secrets exist.

## Verifying a downloaded build

```sh
spctl --assess --type execute -vv /Applications/Claudette.app   # → accepted, source=Notarized Developer ID
xcrun stapler validate /Applications/Claudette.app              # → The validate action worked!
```
