# Sending the board DTS upstream

Status: **ready** (checkpatch 0 errors, 1 expected MAINTAINERS warning).
Identity: `ImAthanasia <imathanasia@users.noreply.github.com>` (GitHub noreply).

## Files
- `0000-cover-letter.md` - cover letter (copy the fenced block into `0000-cover-letter.patch`
  or pass the `.md` after stripping the fences; easiest is `git send-email` with
  `--cover-letter` from a git tree).
- `0001-ARM-dts-armada-370-Add-WD-My-Cloud-EX2-Gen1.patch` - the patch.

## Recommended: send from your own machine (SMTP credentials are yours)

```sh
# one-time: tell git who you are
git config --global user.name  "ImAthanasia"
git config --global user.email "imathanasia@users.noreply.github.com"

# if not already configured, set your SMTP (e.g. Gmail app password)
git config --global sendemail.smtpserver smtp.gmail.com
git config --global sendemail.smtpserverport 587
git config --global sendemail.smtpencryption tls
git config --global sendemail.smtpuser you@gmail.com

git send-email \
  --from="ImAthanasia <imathanasia@users.noreply.github.com>" \
  --to=linux-arm-kernel@lists.infradead.org \
  --to=andrew@lunn.ch \
  --to=gregory.clement@bootlin.com \
  --to=sebastian.hesselbarth@gmail.com \
  --cc=devicetree@vger.kernel.org \
  --cc=robh@kernel.org --cc=krzk+dt@kernel.org --cc=conor+dt@kernel.org \
  --cc=linux-kernel@vger.kernel.org \
  --subject-prefix="PATCH" \
  0001-ARM-dts-armada-370-Add-WD-My-Cloud-EX2-Gen1.patch
```

Notes:
- **Single patch = no cover letter needed.** The `.patch` already starts with `From:` and
  `Subject:`; send it directly. Only add a cover letter if you later send a series.
- `--to` puts maintainers in To; `--cc` keeps the lists in Cc. Kernel lists want plain text;
  git send-email handles that.
- DCO identity: the `Signed-off-by` uses a GitHub noreply address. Maintainers normally
  accept it, but a real name in `user.name` and that address in `user.email` is the safest
  combination; do not change the address after sending or the thread loses continuity.
- Kernel lists require **plain text** (no HTML) - git send-email handles that.
- Expected replies: maintainers may ask for the DTS to be based on a specific parent file
  or to drop the stock partition labels; replies usually arrive within hours/days.

## Monitoring replies
- Search: https://lore.kernel.org/all/?q=s%3A%22Add+WD+My+Cloud+EX2%22
- Or: https://lore.kernel.org/linux-arm-kernel/ (subject search)
- Patchwork: https://patchwork.kernel.org/project/linux-arm-kernel/list/

Check ~5-10 minutes after sending, then again the next day.
