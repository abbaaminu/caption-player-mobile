class AppConfig {
  static const freeTrialDuration = Duration(minutes: 30);
  static const licenseVerificationTimeout = Duration(seconds: 12);

  static const licenseVerificationUrl =
      'https://api.caption.stackbuildco.com/verify';
  static const pricingUrl = 'https://caption.stackbuildco.com/#/pricing';
  static const monthlyPlanLabel = r'Monthly — $1.00 / month';
  static const lifetimePlanLabel = r'Lifetime — $19.00 one-time';
}
