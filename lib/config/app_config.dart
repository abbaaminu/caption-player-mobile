/// Product-wide constants that do not depend on the platform.
abstract final class AppConfig {
  static const appName = 'Live Caption Player';
  static const tagline = 'Watch. Listen. Read every word.';

  /// How much media playback each installation can use before activation.
  static const maxFreeTrialMs = 30 * 60 * 1000;
  static const freeTrialDuration = Duration(milliseconds: maxFreeTrialMs);

  static const licenseVerificationTimeout = Duration(seconds: 12);

  static const licenseVerificationUrl = String.fromEnvironment(
    'LICENSE_VERIFICATION_URL',
    defaultValue: 'https://api.caption.stackbuildco.com/verify',
  );
  static const pricingUrl = String.fromEnvironment(
    'PRICING_URL',
    defaultValue: 'https://caption.stackbuildco.com/#/pricing',
  );

  static const monthlyPlanLabel = r'Monthly — $1.00 / month';
  static const lifetimePlanLabel = r'Lifetime — $19.00 one-time';

  /// Defensive limit so an accidental paste cannot send a huge request.
  static const maxLicenseKeyLength = 256;

  /// Trial progress is written at most once per interval while playing.
  static const trialSaveInterval = Duration(seconds: 5);

  /// Custom URL scheme registered by the Android and iOS projects.
  static const activationScheme = 'captionplayer';
  static const activationHost = 'activate';

  static const supportEmail = 'support@stackbuildco.com';

  /// The compact English Vosk model downloaded on first use and cached locally.
  static const speechModelUrl =
      'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip';
}
