# JagSpoor Roadmap


## 🔴 NOW - Get v10 Live (Priority)
- [ ] Pull main 8e9ec52 (email notifications to support@jag-spoor.co.za)
- [ ] firebase functions:secrets:set EMAIL_PASS + firebase deploy --only functions
- [ ] Test email to support@jag-spoor.co.za via test signup in Auth
- [ ] Wait for Play Console > Publishing overview = Published (v10)
- [ ] Then Firestore admin_config/app_version -> latest_version:10, min_required_version:10, force_update:true, updated_at:now
- [ ] Verify admin_config/review_config: facebook_url https://www.facebook.com/JagSpoor/reviews/, play_store_url https://play.google.com/store/apps/details?id=za.co.jagspoor.app, enabled:true, min_launches:3, cooldown_days:30


## 🟡 NEXT - v10.1 Small Fixes
- [ ] Apply 1-2 small fixes owner mentioned
- [ ] Bump pubspec.yaml version to 10.1.0+11 (keep applicationId za.co.jagspoor.app)
- [ ] flutter analyze 0 errors


## 🟢 FUTURE - International Hunter Mode (On Hold - Do Not Build Yet)
- [ ] Branch: feature/international-hunter (NOT main)
- [ ] Goal: International hunters book LOCAL SA hunts (SA farms/outfitters), not international hunts
- [ ] AppMode enum: saHunter, saOutfitter, internationalHunter
- [ ] Mode service reading admin_config/feature_flags/international_mode_enabled
- [ ] HIDE for international: SAPS tracker, license_applications, bullets, propellants, ammunition/reloading
- [ ] KEEP for international: animals, tracking/spoor, firearms view-only, feature_usage_events, referral_rewards, users, booking local hunts, outfitters, pricing, review modal
- [ ] Settings: SA Hunter | International Hunter switch gated by feature flag
- [ ] Test via flutter build apk --release + Firebase App Distribution (no Play Store publish)
- [ ] When stable: merge to main -> v11 publish


## 💡 Ideas Parking Lot
- [ ] Manual "Rate JagSpoor" button in Settings calling JagSpoorReviewModal.show()
- [ ] USD pricing toggle for internationals
- [ ] WhatsApp review link uses wa.me/27614991558?text=REVIEW: 5 Stars...
