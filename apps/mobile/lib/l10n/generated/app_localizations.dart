import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
  ];

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @previewDestinations.
  ///
  /// In en, this message translates to:
  /// **'Preview destinations'**
  String get previewDestinations;

  /// No description provided for @explore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get explore;

  /// No description provided for @community.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get community;

  /// No description provided for @circle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get circle;

  /// No description provided for @demo.
  ///
  /// In en, this message translates to:
  /// **'DEMO · No live tracking or messages'**
  String get demo;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Where to today?'**
  String get homeTitle;

  /// No description provided for @homeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A little more confidence, wherever you go.'**
  String get homeSubtitle;

  /// No description provided for @whereTo.
  ///
  /// In en, this message translates to:
  /// **'Where are you heading?'**
  String get whereTo;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search demo destinations'**
  String get searchHint;

  /// No description provided for @chooseDestination.
  ///
  /// In en, this message translates to:
  /// **'Choose a destination'**
  String get chooseDestination;

  /// No description provided for @plan.
  ///
  /// In en, this message translates to:
  /// **'Plan a journey'**
  String get plan;

  /// No description provided for @schematic.
  ///
  /// In en, this message translates to:
  /// **'Dhaka · schematic map'**
  String get schematic;

  /// No description provided for @fixtureMap.
  ///
  /// In en, this message translates to:
  /// **'Illustrative route, not navigation'**
  String get fixtureMap;

  /// No description provided for @origin.
  ///
  /// In en, this message translates to:
  /// **'Farmgate'**
  String get origin;

  /// No description provided for @car.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get car;

  /// No description provided for @walk.
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get walk;

  /// No description provided for @aroundYou.
  ///
  /// In en, this message translates to:
  /// **'Around you'**
  String get aroundYou;

  /// No description provided for @coverageHint.
  ///
  /// In en, this message translates to:
  /// **'Community signals help you choose. Streets without reports remain unknown.'**
  String get coverageHint;

  /// No description provided for @routesTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your route'**
  String get routesTitle;

  /// No description provided for @lowerRisk.
  ///
  /// In en, this message translates to:
  /// **'Lower reported risk'**
  String get lowerRisk;

  /// No description provided for @fastest.
  ///
  /// In en, this message translates to:
  /// **'Fastest'**
  String get fastest;

  /// No description provided for @limitedCoverage.
  ///
  /// In en, this message translates to:
  /// **'Limited coverage · No safety guarantee'**
  String get limitedCoverage;

  /// No description provided for @routeNote.
  ///
  /// In en, this message translates to:
  /// **'ETAs and evidence coverage are illustrative. Reports cannot predict every incident.'**
  String get routeNote;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start demo journey'**
  String get start;

  /// No description provided for @loadingRoutes.
  ///
  /// In en, this message translates to:
  /// **'Comparing demo routes…'**
  String get loadingRoutes;

  /// No description provided for @routeError.
  ///
  /// In en, this message translates to:
  /// **'Routes could not be loaded'**
  String get routeError;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline preview · Local drafts still work'**
  String get offline;

  /// No description provided for @offlineNote.
  ///
  /// In en, this message translates to:
  /// **'A new route needs a connection. Restore the normal demo scenario to try again.'**
  String get offlineNote;

  /// No description provided for @errorNote.
  ///
  /// In en, this message translates to:
  /// **'Change the demo scenario or retry to explore this state.'**
  String get errorNote;

  /// No description provided for @journeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Journey in progress'**
  String get journeyTitle;

  /// No description provided for @monitoringDemo.
  ///
  /// In en, this message translates to:
  /// **'Simulated journey · Location sharing off'**
  String get monitoringDemo;

  /// No description provided for @baseline.
  ///
  /// In en, this message translates to:
  /// **'Your chosen route is the monitoring baseline. Background tracking is not connected yet.'**
  String get baseline;

  /// No description provided for @previewDeviation.
  ///
  /// In en, this message translates to:
  /// **'Preview a route deviation'**
  String get previewDeviation;

  /// No description provided for @endJourney.
  ///
  /// In en, this message translates to:
  /// **'End journey'**
  String get endJourney;

  /// No description provided for @deviationTitle.
  ///
  /// In en, this message translates to:
  /// **'Your route has changed'**
  String get deviationTitle;

  /// No description provided for @deviationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A check-in before any escalation.'**
  String get deviationSubtitle;

  /// No description provided for @detourQuestion.
  ///
  /// In en, this message translates to:
  /// **'Are you comfortable with this detour?'**
  String get detourQuestion;

  /// No description provided for @detourBody.
  ///
  /// In en, this message translates to:
  /// **'A detour can be normal. Confirm it if you expected this change. This example uses simulated GPS.'**
  String get detourBody;

  /// No description provided for @acceptDetour.
  ///
  /// In en, this message translates to:
  /// **'I expected this detour'**
  String get acceptDetour;

  /// No description provided for @keepRoute.
  ///
  /// In en, this message translates to:
  /// **'Keep original route'**
  String get keepRoute;

  /// No description provided for @noAutomaticMessage.
  ///
  /// In en, this message translates to:
  /// **'No contact is notified automatically in this demo.'**
  String get noAutomaticMessage;

  /// No description provided for @openSos.
  ///
  /// In en, this message translates to:
  /// **'Open SOS'**
  String get openSos;

  /// No description provided for @sosTitle.
  ///
  /// In en, this message translates to:
  /// **'Request help'**
  String get sosTitle;

  /// No description provided for @sosBody.
  ///
  /// In en, this message translates to:
  /// **'Preview only. No emergency service is connected and no message will be sent.'**
  String get sosBody;

  /// No description provided for @sosConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get sosConfirm;

  /// No description provided for @sosReceipt.
  ///
  /// In en, this message translates to:
  /// **'Demo SOS recorded. No message was sent.'**
  String get sosReceipt;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @communityTitle.
  ///
  /// In en, this message translates to:
  /// **'Your city, together.'**
  String get communityTitle;

  /// No description provided for @communitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Report events. Help others make informed choices.'**
  String get communitySubtitle;

  /// No description provided for @reportIncident.
  ///
  /// In en, this message translates to:
  /// **'Report an incident'**
  String get reportIncident;

  /// No description provided for @unreviewed.
  ///
  /// In en, this message translates to:
  /// **'Unreviewed · Demo report'**
  String get unreviewed;

  /// No description provided for @reviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed · Demo report'**
  String get reviewed;

  /// No description provided for @verificationNote.
  ///
  /// In en, this message translates to:
  /// **'Verified account ≠ verified report. These are illustrative reports.'**
  String get verificationNote;

  /// No description provided for @construction.
  ///
  /// In en, this message translates to:
  /// **'Construction blocks part of the footpath near the crossing.'**
  String get construction;

  /// No description provided for @lights.
  ///
  /// In en, this message translates to:
  /// **'Street lights are out near the crossing.'**
  String get lights;

  /// No description provided for @noReports.
  ///
  /// In en, this message translates to:
  /// **'No reports in this preview'**
  String get noReports;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'No reports means unknown, not safe.'**
  String get unknown;

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'What happened?'**
  String get reportTitle;

  /// No description provided for @reportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Describe the event without identifying people.'**
  String get reportSubtitle;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @place.
  ///
  /// In en, this message translates to:
  /// **'Place'**
  String get place;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @privacyCopy.
  ///
  /// In en, this message translates to:
  /// **'Use demo text only. Do not include faces, names, phone numbers or accusations. This draft stays on this device.'**
  String get privacyCopy;

  /// No description provided for @privacyConsent.
  ///
  /// In en, this message translates to:
  /// **'I understand this is a private demo draft.'**
  String get privacyConsent;

  /// No description provided for @saveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save demo draft'**
  String get saveDraft;

  /// No description provided for @savedDraft.
  ///
  /// In en, this message translates to:
  /// **'Saved on this device. Not published.'**
  String get savedDraft;

  /// No description provided for @drafts.
  ///
  /// In en, this message translates to:
  /// **'Your local drafts'**
  String get drafts;

  /// No description provided for @deleteDrafts.
  ///
  /// In en, this message translates to:
  /// **'Delete local drafts'**
  String get deleteDrafts;

  /// No description provided for @deleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete all demo drafts from this device?'**
  String get deleteConfirm;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @localOnly.
  ///
  /// In en, this message translates to:
  /// **'Private · This device only'**
  String get localOnly;

  /// No description provided for @validation.
  ///
  /// In en, this message translates to:
  /// **'Enter a place and a description of 10–700 characters.'**
  String get validation;

  /// No description provided for @storageError.
  ///
  /// In en, this message translates to:
  /// **'Could not read or save local drafts. Please try again.'**
  String get storageError;

  /// No description provided for @circleTitle.
  ///
  /// In en, this message translates to:
  /// **'Your people, close by'**
  String get circleTitle;

  /// No description provided for @circleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sharing is always your choice.'**
  String get circleSubtitle;

  /// No description provided for @friend.
  ///
  /// In en, this message translates to:
  /// **'Friend · Demo contact'**
  String get friend;

  /// No description provided for @family.
  ///
  /// In en, this message translates to:
  /// **'Family · Demo contact'**
  String get family;

  /// No description provided for @privateTitle.
  ///
  /// In en, this message translates to:
  /// **'Private by default'**
  String get privateTitle;

  /// No description provided for @privateBody.
  ///
  /// In en, this message translates to:
  /// **'No sharing is active. Production invitations will require mutual consent. These contacts are fixtures.'**
  String get privateBody;

  /// No description provided for @demoScenarios.
  ///
  /// In en, this message translates to:
  /// **'Demo scenarios'**
  String get demoScenarios;

  /// No description provided for @normal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get normal;

  /// No description provided for @simulateOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get simulateOffline;

  /// No description provided for @simulateError.
  ///
  /// In en, this message translates to:
  /// **'Route error'**
  String get simulateError;

  /// No description provided for @emptyReports.
  ///
  /// In en, this message translates to:
  /// **'Empty reports'**
  String get emptyReports;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @obstruction.
  ///
  /// In en, this message translates to:
  /// **'Road obstruction'**
  String get obstruction;

  /// No description provided for @lighting.
  ///
  /// In en, this message translates to:
  /// **'Street lighting issue'**
  String get lighting;

  /// No description provided for @theft.
  ///
  /// In en, this message translates to:
  /// **'Theft incident'**
  String get theft;

  /// No description provided for @harassment.
  ///
  /// In en, this message translates to:
  /// **'Harassment'**
  String get harassment;

  /// No description provided for @accident.
  ///
  /// In en, this message translates to:
  /// **'Accident'**
  String get accident;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other event'**
  String get other;

  /// No description provided for @noDestinations.
  ///
  /// In en, this message translates to:
  /// **'No demo destinations match'**
  String get noDestinations;

  /// Illustrative route time and distance.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min · {km} km'**
  String metric(String minutes, String km);

  /// No description provided for @dhakaPilot.
  ///
  /// In en, this message translates to:
  /// **'DHAKA PILOT'**
  String get dhakaPilot;

  /// No description provided for @plannerLabel.
  ///
  /// In en, this message translates to:
  /// **'PLAN YOUR WAY'**
  String get plannerLabel;

  /// No description provided for @savedPlaces.
  ///
  /// In en, this message translates to:
  /// **'Quick destinations'**
  String get savedPlaces;

  /// No description provided for @savedLake.
  ///
  /// In en, this message translates to:
  /// **'Lake'**
  String get savedLake;

  /// No description provided for @savedCampus.
  ///
  /// In en, this message translates to:
  /// **'Campus'**
  String get savedCampus;

  /// No description provided for @savedMetro.
  ///
  /// In en, this message translates to:
  /// **'Metro'**
  String get savedMetro;

  /// No description provided for @selectedDestination.
  ///
  /// In en, this message translates to:
  /// **'Selected destination'**
  String get selectedDestination;

  /// No description provided for @resetMap.
  ///
  /// In en, this message translates to:
  /// **'Reset map view'**
  String get resetMap;

  /// No description provided for @zoomMap.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomMap;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;

  /// No description provided for @mapDemoLabel.
  ///
  /// In en, this message translates to:
  /// **'Illustrative map'**
  String get mapDemoLabel;

  /// No description provided for @mapSignals.
  ///
  /// In en, this message translates to:
  /// **'Demo road reports'**
  String get mapSignals;

  /// No description provided for @routePreview.
  ///
  /// In en, this message translates to:
  /// **'ROUTE PREVIEW'**
  String get routePreview;

  /// No description provided for @journeyOverview.
  ///
  /// In en, this message translates to:
  /// **'JOURNEY OVERVIEW'**
  String get journeyOverview;

  /// No description provided for @travelTime.
  ///
  /// In en, this message translates to:
  /// **'Travel time'**
  String get travelTime;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get minutesShort;

  /// No description provided for @distanceShort.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get distanceShort;

  /// No description provided for @routeChoiceNote.
  ///
  /// In en, this message translates to:
  /// **'Choose what works for you.'**
  String get routeChoiceNote;

  /// No description provided for @fromLabel.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get fromLabel;

  /// No description provided for @toLabel.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get toLabel;

  /// No description provided for @coverageLabel.
  ///
  /// In en, this message translates to:
  /// **'Evidence coverage'**
  String get coverageLabel;

  /// No description provided for @extraTime.
  ///
  /// In en, this message translates to:
  /// **'A little longer, fewer reported concerns.'**
  String get extraTime;

  /// No description provided for @fastestNote.
  ///
  /// In en, this message translates to:
  /// **'Less travel time on the demo network.'**
  String get fastestNote;

  /// No description provided for @allReports.
  ///
  /// In en, this message translates to:
  /// **'All reports'**
  String get allReports;

  /// No description provided for @communitySignals.
  ///
  /// In en, this message translates to:
  /// **'Around Dhaka'**
  String get communitySignals;

  /// No description provided for @sharingOff.
  ///
  /// In en, this message translates to:
  /// **'Sharing off'**
  String get sharingOff;

  /// No description provided for @yourCircle.
  ///
  /// In en, this message translates to:
  /// **'YOUR CIRCLE'**
  String get yourCircle;

  /// No description provided for @circlePeople.
  ///
  /// In en, this message translates to:
  /// **'People you trust'**
  String get circlePeople;

  /// No description provided for @journeyActions.
  ///
  /// In en, this message translates to:
  /// **'Journey controls'**
  String get journeyActions;

  /// No description provided for @checkInLabel.
  ///
  /// In en, this message translates to:
  /// **'ROUTE CHECK-IN'**
  String get checkInLabel;

  /// No description provided for @reportBasics.
  ///
  /// In en, this message translates to:
  /// **'Event details'**
  String get reportBasics;

  /// No description provided for @reportPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Private until you decide'**
  String get reportPrivacyTitle;

  /// No description provided for @reportPrivacyCaption.
  ///
  /// In en, this message translates to:
  /// **'This draft stays on your device.'**
  String get reportPrivacyCaption;

  /// No description provided for @accountOpen.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountOpen;

  /// No description provided for @accountTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Awaaz account'**
  String get accountTitle;

  /// No description provided for @accountSetup.
  ///
  /// In en, this message translates to:
  /// **'Accounts are not connected in this preview yet.'**
  String get accountSetup;

  /// No description provided for @accountSetupBody.
  ///
  /// In en, this message translates to:
  /// **'You can still explore demo journeys and private demo drafts.'**
  String get accountSetupBody;

  /// No description provided for @accountSignIn.
  ///
  /// In en, this message translates to:
  /// **'Continue with your phone'**
  String get accountSignIn;

  /// No description provided for @accountSignInBody.
  ///
  /// In en, this message translates to:
  /// **'A code confirms control of your phone. It does not verify reports or enable location sharing.'**
  String get accountSignInBody;

  /// No description provided for @accountPhone.
  ///
  /// In en, this message translates to:
  /// **'Bangladesh mobile number'**
  String get accountPhone;

  /// No description provided for @accountSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send a code'**
  String get accountSendCode;

  /// No description provided for @accountCode.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get accountCode;

  /// No description provided for @accountVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify and continue'**
  String get accountVerify;

  /// No description provided for @accountChangePhone.
  ///
  /// In en, this message translates to:
  /// **'Use another number'**
  String get accountChangePhone;

  /// No description provided for @accountName.
  ///
  /// In en, this message translates to:
  /// **'Your display name'**
  String get accountName;

  /// No description provided for @accountAdult.
  ///
  /// In en, this message translates to:
  /// **'I am 18 or older.'**
  String get accountAdult;

  /// No description provided for @accountSaveProfile.
  ///
  /// In en, this message translates to:
  /// **'Save profile'**
  String get accountSaveProfile;

  /// No description provided for @accountProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get accountProfile;

  /// No description provided for @accountCircles.
  ///
  /// In en, this message translates to:
  /// **'Trusted Circles'**
  String get accountCircles;

  /// No description provided for @accountReports.
  ///
  /// In en, this message translates to:
  /// **'My reports'**
  String get accountReports;

  /// No description provided for @accountSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out on this device'**
  String get accountSignOut;

  /// No description provided for @accountPhoneVerified.
  ///
  /// In en, this message translates to:
  /// **'Phone confirmed'**
  String get accountPhoneVerified;

  /// No description provided for @accountPhoneVerify.
  ///
  /// In en, this message translates to:
  /// **'Confirm your phone before submitting a report.'**
  String get accountPhoneVerify;

  /// No description provided for @accountConnectionCode.
  ///
  /// In en, this message translates to:
  /// **'Your connection code'**
  String get accountConnectionCode;

  /// No description provided for @accountCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get accountCopy;

  /// No description provided for @accountCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get accountCopied;

  /// No description provided for @accountNewCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle name'**
  String get accountNewCircle;

  /// No description provided for @accountCreateCircle.
  ///
  /// In en, this message translates to:
  /// **'Create a Circle'**
  String get accountCreateCircle;

  /// No description provided for @accountNoCircles.
  ///
  /// In en, this message translates to:
  /// **'No Circles yet. Invite someone you trust.'**
  String get accountNoCircles;

  /// No description provided for @accountRecipient.
  ///
  /// In en, this message translates to:
  /// **'Their connection code'**
  String get accountRecipient;

  /// No description provided for @accountInvite.
  ///
  /// In en, this message translates to:
  /// **'Create an invitation'**
  String get accountInvite;

  /// No description provided for @accountInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Share this code with the invited person.'**
  String get accountInviteCode;

  /// No description provided for @accountInvitations.
  ///
  /// In en, this message translates to:
  /// **'Invitations for you'**
  String get accountInvitations;

  /// No description provided for @accountAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept with code'**
  String get accountAccept;

  /// No description provided for @accountDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get accountDecline;

  /// No description provided for @accountInviteSecret.
  ///
  /// In en, this message translates to:
  /// **'Invitation code'**
  String get accountInviteSecret;

  /// No description provided for @accountMembershipPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Joining a Circle does not share your location.'**
  String get accountMembershipPrivacy;

  /// No description provided for @accountRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get accountRemove;

  /// No description provided for @accountLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave Circle'**
  String get accountLeave;

  /// No description provided for @accountCloseCircle.
  ///
  /// In en, this message translates to:
  /// **'Close Circle'**
  String get accountCloseCircle;

  /// No description provided for @accountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm this change?'**
  String get accountConfirm;

  /// No description provided for @accountNoReports.
  ///
  /// In en, this message translates to:
  /// **'You have no submitted reports.'**
  String get accountNoReports;

  /// No description provided for @accountPending.
  ///
  /// In en, this message translates to:
  /// **'Pending review · Private'**
  String get accountPending;

  /// No description provided for @accountReviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get accountReviewed;

  /// No description provided for @accountRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected · Private'**
  String get accountRejected;

  /// No description provided for @accountWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw report'**
  String get accountWithdraw;

  /// No description provided for @accountWithdrawalBody.
  ///
  /// In en, this message translates to:
  /// **'This removes your submitted text and location, and its linked public event. A retry will not restore them.'**
  String get accountWithdrawalBody;

  /// No description provided for @accountMoreReports.
  ///
  /// In en, this message translates to:
  /// **'Load more reports'**
  String get accountMoreReports;

  /// No description provided for @accountPublished.
  ///
  /// In en, this message translates to:
  /// **'Published road reports'**
  String get accountPublished;

  /// No description provided for @accountManage.
  ///
  /// In en, this message translates to:
  /// **'Manage my account and Circles'**
  String get accountManage;

  /// No description provided for @accountEmptyEvents.
  ///
  /// In en, this message translates to:
  /// **'No published reports. Road conditions remain unknown.'**
  String get accountEmptyEvents;

  /// No description provided for @accountPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid Bangladesh mobile number.'**
  String get accountPhoneInvalid;

  /// No description provided for @accountCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Check the code and try again.'**
  String get accountCodeInvalid;

  /// No description provided for @accountRateLimit.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait before trying again.'**
  String get accountRateLimit;

  /// No description provided for @accountRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not complete this request. Check the details and retry.'**
  String get accountRequestFailed;

  /// No description provided for @accountNetwork.
  ///
  /// In en, this message translates to:
  /// **'Account services could not be reached. Check your connection and retry.'**
  String get accountNetwork;

  /// No description provided for @accountInviteUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This invitation is no longer available. Ask for a new one.'**
  String get accountInviteUnavailable;

  /// No description provided for @accountInviteExists.
  ///
  /// In en, this message translates to:
  /// **'An invitation is already pending for this person.'**
  String get accountInviteExists;

  /// No description provided for @accountAlreadyJoined.
  ///
  /// In en, this message translates to:
  /// **'This person is already a member.'**
  String get accountAlreadyJoined;

  /// No description provided for @accountLimit.
  ///
  /// In en, this message translates to:
  /// **'This Circle or account has reached its current limit.'**
  String get accountLimit;

  /// No description provided for @accountOwnerMustClose.
  ///
  /// In en, this message translates to:
  /// **'The owner must close the Circle rather than leave it.'**
  String get accountOwnerMustClose;

  /// No description provided for @accountLogoutPending.
  ///
  /// In en, this message translates to:
  /// **'Signed out locally. Server sign-out could not be confirmed.'**
  String get accountLogoutPending;

  /// No description provided for @accountPreviewStatus.
  ///
  /// In en, this message translates to:
  /// **'Preview routes · No live tracking or alerts'**
  String get accountPreviewStatus;

  /// No description provided for @accountSavedWrites.
  ///
  /// In en, this message translates to:
  /// **'Saved requests'**
  String get accountSavedWrites;

  /// No description provided for @accountSavedWritesBody.
  ///
  /// In en, this message translates to:
  /// **'Stored privately on this device. Nothing resends automatically. A request may already have arrived; retry uses the same request ID.'**
  String get accountSavedWritesBody;

  /// No description provided for @accountRemoveRetry.
  ///
  /// In en, this message translates to:
  /// **'Remove saved request'**
  String get accountRemoveRetry;

  /// No description provided for @accountRemoveRetryBody.
  ///
  /// In en, this message translates to:
  /// **'Remove this device\'s saved request? This does not undo anything already received by the server. Check your Circles or report history before submitting again.'**
  String get accountRemoveRetryBody;

  /// No description provided for @accountSavedCircle.
  ///
  /// In en, this message translates to:
  /// **'Create Circle'**
  String get accountSavedCircle;

  /// No description provided for @accountSavedInvite.
  ///
  /// In en, this message translates to:
  /// **'Circle invitation'**
  String get accountSavedInvite;

  /// No description provided for @accountSavedReport.
  ///
  /// In en, this message translates to:
  /// **'Road report'**
  String get accountSavedReport;

  /// No description provided for @accountSavedLocation.
  ///
  /// In en, this message translates to:
  /// **'Reported location'**
  String get accountSavedLocation;

  /// No description provided for @accountRetryOld.
  ///
  /// In en, this message translates to:
  /// **'This report is over 72 hours old. Check your report history; its original observation time will not be changed.'**
  String get accountRetryOld;

  /// No description provided for @accountStorage.
  ///
  /// In en, this message translates to:
  /// **'Private storage is unavailable. No replacement request will be sent. Retry after checking device storage.'**
  String get accountStorage;

  /// No description provided for @accountRetryCleanup.
  ///
  /// In en, this message translates to:
  /// **'The server received the request, but its saved copy could not be cleared. Retrying this copy uses the same ID.'**
  String get accountRetryCleanup;

  /// No description provided for @accountRetryLimit.
  ///
  /// In en, this message translates to:
  /// **'Saved requests have reached the device limit. Review them before adding more.'**
  String get accountRetryLimit;

  /// No description provided for @accountWithdrawnReceipt.
  ///
  /// In en, this message translates to:
  /// **'This report was already withdrawn. Retrying did not restore it.'**
  String get accountWithdrawnReceipt;

  /// No description provided for @accountCheckStatus.
  ///
  /// In en, this message translates to:
  /// **'Check status'**
  String get accountCheckStatus;

  /// No description provided for @accountReportNotReceived.
  ///
  /// In en, this message translates to:
  /// **'No server receipt was found. This report is too old to send; check history before removing its saved request.'**
  String get accountReportNotReceived;

  /// No description provided for @composeOpen.
  ///
  /// In en, this message translates to:
  /// **'Submit a road report'**
  String get composeOpen;

  /// No description provided for @composeTitle.
  ///
  /// In en, this message translates to:
  /// **'Report a road condition'**
  String get composeTitle;

  /// No description provided for @composeBody.
  ///
  /// In en, this message translates to:
  /// **'Report what you observed here, just now. Your report stays private until reviewed. Avoid names, faces or accusations about individuals.'**
  String get composeBody;

  /// No description provided for @composeLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my current location'**
  String get composeLocation;

  /// No description provided for @composeLocationPurpose.
  ///
  /// In en, this message translates to:
  /// **'Location is collected only when you tap this button, to place this report on the right road. It is not shared with your Circle.'**
  String get composeLocationPurpose;

  /// No description provided for @composeLocated.
  ///
  /// In en, this message translates to:
  /// **'Current location captured'**
  String get composeLocated;

  /// No description provided for @composePrecision.
  ///
  /// In en, this message translates to:
  /// **'Estimated accuracy'**
  String get composePrecision;

  /// No description provided for @composeConsent.
  ///
  /// In en, this message translates to:
  /// **'I observed this condition here and agree to submit this text and location for review.'**
  String get composeConsent;

  /// No description provided for @composeSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit privately for review'**
  String get composeSubmit;

  /// No description provided for @composeSuccess.
  ///
  /// In en, this message translates to:
  /// **'Report received for private review.'**
  String get composeSuccess;

  /// No description provided for @composeSaved.
  ///
  /// In en, this message translates to:
  /// **'View saved requests and report history'**
  String get composeSaved;

  /// No description provided for @composeTestLocation.
  ///
  /// In en, this message translates to:
  /// **'Synthetic test location'**
  String get composeTestLocation;

  /// No description provided for @composePermission.
  ///
  /// In en, this message translates to:
  /// **'Location access was declined. You can continue using the rest of Awaaz.'**
  String get composePermission;

  /// No description provided for @composePermanent.
  ///
  /// In en, this message translates to:
  /// **'Location access is disabled for Awaaz. Enable it in app settings if you want to place this report.'**
  String get composePermanent;

  /// No description provided for @composeDisabled.
  ///
  /// In en, this message translates to:
  /// **'Location services are off. Turn them on, then capture your location again.'**
  String get composeDisabled;

  /// No description provided for @composeApproximate.
  ///
  /// In en, this message translates to:
  /// **'Approximate location cannot identify the road reliably. Choose precise access in app settings to submit this report.'**
  String get composeApproximate;

  /// No description provided for @composeInaccurate.
  ///
  /// In en, this message translates to:
  /// **'This location is too uncertain to identify the road. Try again with a clearer GPS signal.'**
  String get composeInaccurate;

  /// No description provided for @composeStale.
  ///
  /// In en, this message translates to:
  /// **'Capture your current location again before submitting.'**
  String get composeStale;

  /// No description provided for @composeMocked.
  ///
  /// In en, this message translates to:
  /// **'A simulated location cannot be used for a live report.'**
  String get composeMocked;

  /// No description provided for @composeOutside.
  ///
  /// In en, this message translates to:
  /// **'Road reporting is currently available within the Dhaka pilot area.'**
  String get composeOutside;

  /// No description provided for @composeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'A current location could not be captured. Try again when location services are available.'**
  String get composeUnavailable;

  /// No description provided for @composeAppSettings.
  ///
  /// In en, this message translates to:
  /// **'Open app settings'**
  String get composeAppSettings;

  /// No description provided for @composeLocationSettings.
  ///
  /// In en, this message translates to:
  /// **'Open location settings'**
  String get composeLocationSettings;

  /// No description provided for @nativeActive.
  ///
  /// In en, this message translates to:
  /// **'On-device route checks active'**
  String get nativeActive;

  /// No description provided for @nativeOff.
  ///
  /// In en, this message translates to:
  /// **'Background route checks off'**
  String get nativeOff;

  /// No description provided for @nativeStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Monitoring status unavailable'**
  String get nativeStatusUnknown;

  /// No description provided for @nativeStatusUnknownBody.
  ///
  /// In en, this message translates to:
  /// **'We could not confirm whether background route checks are running. Try again to check the current status before relying on alerts.'**
  String get nativeStatusUnknownBody;

  /// No description provided for @nativeCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Is this detour expected?'**
  String get nativeCheckIn;

  /// No description provided for @nativeInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Journey monitoring was interrupted'**
  String get nativeInterrupted;

  /// No description provided for @nativeUncertain.
  ///
  /// In en, this message translates to:
  /// **'Waiting for reliable location'**
  String get nativeUncertain;

  /// No description provided for @nativePrivate.
  ///
  /// In en, this message translates to:
  /// **'Checks run on this device. Circle sharing and contact escalation are off. You can stop from the ongoing notification.'**
  String get nativePrivate;

  /// No description provided for @nativeArmBody.
  ///
  /// In en, this message translates to:
  /// **'Starting this journey will request location and notification access, and show an ongoing monitoring notification.'**
  String get nativeArmBody;

  /// No description provided for @nativeNoCorridor.
  ///
  /// In en, this message translates to:
  /// **'This preview route has no approved street corridor. It cannot arm background GPS checks.'**
  String get nativeNoCorridor;

  /// No description provided for @nativeFixture.
  ///
  /// In en, this message translates to:
  /// **'Synthetic corridor test · no sharing or contact delivery'**
  String get nativeFixture;

  /// No description provided for @nativeNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable journey notifications before arming background alerts.'**
  String get nativeNotifications;

  /// No description provided for @nativeLocation.
  ///
  /// In en, this message translates to:
  /// **'Precise foreground location access is required to start monitoring.'**
  String get nativeLocation;

  /// No description provided for @nativeVisible.
  ///
  /// In en, this message translates to:
  /// **'Open Awaaz before starting or changing journey monitoring.'**
  String get nativeVisible;

  /// No description provided for @nativeUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Native journey monitoring is currently available on Android.'**
  String get nativeUnsupported;

  /// No description provided for @nativeFailure.
  ///
  /// In en, this message translates to:
  /// **'Monitoring could not complete this action. Check its status before relying on route alerts.'**
  String get nativeFailure;

  /// No description provided for @nativeKeepWatching.
  ///
  /// In en, this message translates to:
  /// **'Keep watching this route'**
  String get nativeKeepWatching;

  /// No description provided for @nativeStop.
  ///
  /// In en, this message translates to:
  /// **'Stop monitoring'**
  String get nativeStop;

  /// No description provided for @mapUseLocation.
  ///
  /// In en, this message translates to:
  /// **'Show my location'**
  String get mapUseLocation;

  /// No description provided for @mapTraffic.
  ///
  /// In en, this message translates to:
  /// **'Traffic'**
  String get mapTraffic;

  /// No description provided for @mapUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The map could not respond. Check your connection and try again.'**
  String get mapUnavailable;

  /// No description provided for @mapLocating.
  ///
  /// In en, this message translates to:
  /// **'Finding your location'**
  String get mapLocating;

  /// No description provided for @mapLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'A reliable current location could not be found. Try again with a clearer GPS signal.'**
  String get mapLocationUnavailable;

  /// No description provided for @mapLocationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location access was declined. You can still browse the map.'**
  String get mapLocationDenied;

  /// No description provided for @mapMyLocation.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get mapMyLocation;

  /// No description provided for @mapLocationPurpose.
  ///
  /// In en, this message translates to:
  /// **'Show your location on Google Maps while this map is visible. Google processes map and location data to provide this view. This does not start a journey or share your location with your Circle.'**
  String get mapLocationPurpose;

  /// No description provided for @mapPreviewStatus.
  ///
  /// In en, this message translates to:
  /// **'Google Maps · Journeys and sharing are previews'**
  String get mapPreviewStatus;

  /// No description provided for @mapStopLocation.
  ///
  /// In en, this message translates to:
  /// **'Stop showing my location'**
  String get mapStopLocation;

  /// No description provided for @communityLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading road reports'**
  String get communityLoading;

  /// No description provided for @circleMember.
  ///
  /// In en, this message translates to:
  /// **'Joined Circle'**
  String get circleMember;

  /// No description provided for @communityPublished.
  ///
  /// In en, this message translates to:
  /// **'Published road report'**
  String get communityPublished;

  /// No description provided for @communityObserved.
  ///
  /// In en, this message translates to:
  /// **'Observed'**
  String get communityObserved;

  /// No description provided for @communityFinishSetup.
  ///
  /// In en, this message translates to:
  /// **'Finish account setup'**
  String get communityFinishSetup;

  /// No description provided for @communityFeedIntro.
  ///
  /// In en, this message translates to:
  /// **'Reported road conditions in Dhaka.'**
  String get communityFeedIntro;

  /// No description provided for @communitySignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in and complete your profile to read published road reports and manage your submissions.'**
  String get communitySignIn;

  /// No description provided for @circleSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to create a Circle, review invitations and choose who joins.'**
  String get circleSignIn;

  /// No description provided for @circleOwner.
  ///
  /// In en, this message translates to:
  /// **'You manage this Circle'**
  String get circleOwner;

  /// No description provided for @communityPublishedNote.
  ///
  /// In en, this message translates to:
  /// **'Published reports expire. They describe observations, not a guarantee of safety.'**
  String get communityPublishedNote;

  /// No description provided for @journeyPlannedEstimate.
  ///
  /// In en, this message translates to:
  /// **'Planned estimate; not live remaining time'**
  String get journeyPlannedEstimate;

  /// No description provided for @journeyPreviewChecks.
  ///
  /// In en, this message translates to:
  /// **'Preview journey. Background GPS checks and Circle sharing are off.'**
  String get journeyPreviewChecks;

  /// No description provided for @journeyEnding.
  ///
  /// In en, this message translates to:
  /// **'Stopping monitoring…'**
  String get journeyEnding;

  /// No description provided for @journeyNativeDetour.
  ///
  /// In en, this message translates to:
  /// **'A detour can be normal. Your chosen route stays selected; no contacts are notified.'**
  String get journeyNativeDetour;

  /// No description provided for @journeyArmTitle.
  ///
  /// In en, this message translates to:
  /// **'Start background route checks?'**
  String get journeyArmTitle;

  /// No description provided for @journeyStartNative.
  ///
  /// In en, this message translates to:
  /// **'Start monitoring'**
  String get journeyStartNative;

  /// No description provided for @journeyStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting journey…'**
  String get journeyStarting;

  /// No description provided for @journeyNativeStatus.
  ///
  /// In en, this message translates to:
  /// **'On-device checks · Sharing and contact delivery off'**
  String get journeyNativeStatus;

  /// No description provided for @geoPinnedDestination.
  ///
  /// In en, this message translates to:
  /// **'Pinned destination'**
  String get geoPinnedDestination;

  /// No description provided for @geoRoutesTitle.
  ///
  /// In en, this message translates to:
  /// **'Your street route'**
  String get geoRoutesTitle;

  /// No description provided for @geoCurrentOrigin.
  ///
  /// In en, this message translates to:
  /// **'Current location'**
  String get geoCurrentOrigin;

  /// No description provided for @geoStatus.
  ///
  /// In en, this message translates to:
  /// **'Street routing · Safety evidence unknown'**
  String get geoStatus;

  /// No description provided for @geoUnknownSafety.
  ///
  /// In en, this message translates to:
  /// **'Safety coverage unknown. This is not a safety-ranked route.'**
  String get geoUnknownSafety;

  /// No description provided for @geoEstimate.
  ///
  /// In en, this message translates to:
  /// **'Static OSM estimate; live traffic is not included.'**
  String get geoEstimate;

  /// No description provided for @geoMapUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Geographic map display is unavailable. You can enter a destination\'s coordinates in the Dhaka pilot area.'**
  String get geoMapUnavailable;

  /// No description provided for @geoChoosePin.
  ///
  /// In en, this message translates to:
  /// **'Choose a road or entrance'**
  String get geoChoosePin;

  /// No description provided for @geoPinHint.
  ///
  /// In en, this message translates to:
  /// **'Search for a place or hold the map to choose an arrival point in Dhaka.'**
  String get geoPinHint;

  /// No description provided for @geoUsePin.
  ///
  /// In en, this message translates to:
  /// **'Use this destination'**
  String get geoUsePin;

  /// No description provided for @geoLatitude.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get geoLatitude;

  /// No description provided for @geoLongitude.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get geoLongitude;

  /// No description provided for @geoPlanConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan from your current location?'**
  String get geoPlanConsentTitle;

  /// No description provided for @geoPlanConsentBody.
  ///
  /// In en, this message translates to:
  /// **'Use one fresh, precise location fix and send it with your destination to the Awaaz routing server. Google processes map data for the map view. Planning does not start background checks, save a trip history or share your location with your Circle.'**
  String get geoPlanConsentBody;

  /// No description provided for @geoUseOrigin.
  ///
  /// In en, this message translates to:
  /// **'Use current location'**
  String get geoUseOrigin;

  /// No description provided for @geoLoading.
  ///
  /// In en, this message translates to:
  /// **'Finding a fresh origin and planning a street route…'**
  String get geoLoading;

  /// No description provided for @geoRoutingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Street routing is unavailable. Check the connection and try again. No demo route has been substituted.'**
  String get geoRoutingUnavailable;

  /// No description provided for @geoSnapTooFar.
  ///
  /// In en, this message translates to:
  /// **'A nearby routable road could not be found. Choose a road or entrance closer to your destination, or retry with a clearer origin fix.'**
  String get geoSnapTooFar;

  /// No description provided for @geoAlreadyThere.
  ///
  /// In en, this message translates to:
  /// **'You are already close to this destination. Choose another destination to plan a route.'**
  String get geoAlreadyThere;

  /// No description provided for @geoOutside.
  ///
  /// In en, this message translates to:
  /// **'This route is outside the Dhaka pilot area.'**
  String get geoOutside;

  /// No description provided for @geoEnableLocation.
  ///
  /// In en, this message translates to:
  /// **'Turn on location services to plan from your current position.'**
  String get geoEnableLocation;

  /// No description provided for @geoPlanningCanceled.
  ///
  /// In en, this message translates to:
  /// **'Planning was cancelled. Retry explicitly to acquire a fresh location.'**
  String get geoPlanningCanceled;

  /// No description provided for @geoExpired.
  ///
  /// In en, this message translates to:
  /// **'This route plan expired. Plan again before starting background checks.'**
  String get geoExpired;

  /// No description provided for @geoMockMonitoring.
  ///
  /// In en, this message translates to:
  /// **'Test GPS can preview routes, but cannot arm production background checks. Use a physical phone with reliable location.'**
  String get geoMockMonitoring;

  /// No description provided for @geoReportedChoice.
  ///
  /// In en, this message translates to:
  /// **'Fewer reported issues'**
  String get geoReportedChoice;

  /// No description provided for @geoTestDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Test reports · Safety unknown'**
  String get geoTestDisclosure;

  /// No description provided for @geoExperimentalDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Experimental · Safety unknown'**
  String get geoExperimentalDisclosure;

  /// No description provided for @geoReportCoverage.
  ///
  /// In en, this message translates to:
  /// **'Reviewed observations on {percent}% of this route'**
  String geoReportCoverage(int percent);

  /// No description provided for @geoReportedNote.
  ///
  /// In en, this message translates to:
  /// **'Experimental comparison using reviewed reports. Unreported streets remain unknown; neither option guarantees safety.'**
  String get geoReportedNote;

  /// No description provided for @geoSyntheticReports.
  ///
  /// In en, this message translates to:
  /// **'Test reports · These observations are synthetic, not live Dhaka incidents.'**
  String get geoSyntheticReports;

  /// No description provided for @placeSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search Dhaka'**
  String get placeSearchTitle;

  /// No description provided for @placeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search places or roads'**
  String get placeSearchHint;

  /// No description provided for @placeSearchPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Search words are sent to Awaaz. Results use imported OpenStreetMap data and may be incomplete.'**
  String get placeSearchPrivacy;

  /// No description provided for @placeStart.
  ///
  /// In en, this message translates to:
  /// **'Enter at least two characters to find a place or road.'**
  String get placeStart;

  /// No description provided for @placeNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching imported places. Try another name or choose a pin on the map.'**
  String get placeNoResults;

  /// No description provided for @placeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Place search is unavailable. Retry or choose a pin on the map.'**
  String get placeUnavailable;

  /// No description provided for @placeClear.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get placeClear;

  /// No description provided for @placePaused.
  ///
  /// In en, this message translates to:
  /// **'Search paused while you were away. Tap Retry to search again.'**
  String get placePaused;

  /// No description provided for @placeReviewPin.
  ///
  /// In en, this message translates to:
  /// **'Check this arrival point. Hold the map to move it to the road or entrance you want.'**
  String get placeReviewPin;

  /// No description provided for @placeRoad.
  ///
  /// In en, this message translates to:
  /// **'Road'**
  String get placeRoad;

  /// No description provided for @placeEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get placeEducation;

  /// No description provided for @placeHealth.
  ///
  /// In en, this message translates to:
  /// **'Health facility'**
  String get placeHealth;

  /// No description provided for @placeTransit.
  ///
  /// In en, this message translates to:
  /// **'Transit stop'**
  String get placeTransit;

  /// No description provided for @placeShop.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get placeShop;

  /// No description provided for @placeArea.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get placeArea;

  /// No description provided for @placePublic.
  ///
  /// In en, this message translates to:
  /// **'Mapped place'**
  String get placePublic;

  /// No description provided for @routeChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Change route'**
  String get routeChangeTitle;

  /// No description provided for @routeChangeBody.
  ///
  /// In en, this message translates to:
  /// **'Find routes from your current location to the same destination. Looking up or selecting a route does not change the monitoring baseline.'**
  String get routeChangeBody;

  /// No description provided for @routeChangeCurrent.
  ///
  /// In en, this message translates to:
  /// **'Original monitored route'**
  String get routeChangeCurrent;

  /// No description provided for @routeChangeFind.
  ///
  /// In en, this message translates to:
  /// **'Find updated routes'**
  String get routeChangeFind;

  /// No description provided for @routeChangeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Replace monitored route?'**
  String get routeChangeConfirm;

  /// No description provided for @routeChangeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The selected route will become the new monitoring baseline. Route checks restart on that corridor only after Android confirms the change.'**
  String get routeChangeConfirmBody;

  /// No description provided for @routeChangeUse.
  ///
  /// In en, this message translates to:
  /// **'Use this route'**
  String get routeChangeUse;

  /// No description provided for @routeChangeUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'The route change is not confirmed. Check monitoring status before trying again.'**
  String get routeChangeUnconfirmed;

  /// No description provided for @routeChangeNotApplied.
  ///
  /// In en, this message translates to:
  /// **'Android confirms the original route is still monitored. You can retry or return to your journey.'**
  String get routeChangeNotApplied;

  /// No description provided for @routeChangeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The journey or monitored route has changed. Return to the journey before finding another route.'**
  String get routeChangeUnavailable;

  /// No description provided for @routeChangeCheck.
  ///
  /// In en, this message translates to:
  /// **'Check monitoring status'**
  String get routeChangeCheck;

  /// No description provided for @routeChangeApplied.
  ///
  /// In en, this message translates to:
  /// **'Monitored route updated'**
  String get routeChangeApplied;

  /// No description provided for @routeChangeExpired.
  ///
  /// In en, this message translates to:
  /// **'This route plan expired. Find updated routes before changing the monitoring baseline.'**
  String get routeChangeExpired;

  /// No description provided for @blocksTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked accounts'**
  String get blocksTitle;

  /// No description provided for @blocksBody.
  ///
  /// In en, this message translates to:
  /// **'Manage who can join a Circle with you. Unblocking never restores membership or an old invitation.'**
  String get blocksBody;

  /// No description provided for @blocksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No blocked accounts'**
  String get blocksEmpty;

  /// No description provided for @blocksEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'You can block a member from their Circle or block the sender of an invitation.'**
  String get blocksEmptyBody;

  /// No description provided for @blockAccount.
  ///
  /// In en, this message translates to:
  /// **'Block account'**
  String get blockAccount;

  /// No description provided for @unblockAccount.
  ///
  /// In en, this message translates to:
  /// **'Unblock account'**
  String get unblockAccount;

  /// No description provided for @blockConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You will no longer share a Circle. They will be removed from Circles you own; you will leave other Circles you share. Conflicting invitations will be revoked.'**
  String get blockConfirmBody;

  /// No description provided for @unblockConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This removes your block. It does not rejoin a Circle or restore invitations. Connecting again requires a new invitation and acceptance.'**
  String get unblockConfirmBody;

  /// No description provided for @blockedUnknownName.
  ///
  /// In en, this message translates to:
  /// **'Blocked account'**
  String get blockedUnknownName;

  /// No description provided for @blocksLoad.
  ///
  /// In en, this message translates to:
  /// **'Load blocked accounts'**
  String get blocksLoad;

  /// No description provided for @blocksMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get blocksMore;

  /// No description provided for @blockUnconfirmedTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact change not confirmed'**
  String get blockUnconfirmedTitle;

  /// No description provided for @blockUnconfirmedBody.
  ///
  /// In en, this message translates to:
  /// **'Circle details are hidden while the result is uncertain. Check the current decision or explicitly retry the same request. No request is resent automatically.'**
  String get blockUnconfirmedBody;

  /// No description provided for @blockCheck.
  ///
  /// In en, this message translates to:
  /// **'Check decision'**
  String get blockCheck;

  /// No description provided for @blockRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry this decision'**
  String get blockRetry;

  /// No description provided for @blockChanged.
  ///
  /// In en, this message translates to:
  /// **'This decision changed elsewhere. Check it again before making another change.'**
  String get blockChanged;

  /// No description provided for @blockLimit.
  ///
  /// In en, this message translates to:
  /// **'Your blocked-account limit has been reached.'**
  String get blockLimit;

  /// No description provided for @blockVersionLimit.
  ///
  /// In en, this message translates to:
  /// **'This decision cannot be changed further. Contact support.'**
  String get blockVersionLimit;

  /// No description provided for @blockUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This account or decision is no longer available.'**
  String get blockUnavailable;

  /// No description provided for @shareTitle.
  ///
  /// In en, this message translates to:
  /// **'Trip sharing'**
  String get shareTitle;

  /// No description provided for @shareHeadline.
  ///
  /// In en, this message translates to:
  /// **'Let your people know where you are.'**
  String get shareHeadline;

  /// No description provided for @shareForeground.
  ///
  /// In en, this message translates to:
  /// **'Location updates run while this screen is open. Leaving the screen or locking your phone pauses updates. Sharing ends at the chosen time.'**
  String get shareForeground;

  /// No description provided for @shareActive.
  ///
  /// In en, this message translates to:
  /// **'Sharing is on'**
  String get shareActive;

  /// No description provided for @shareUntil.
  ///
  /// In en, this message translates to:
  /// **'Until {time}'**
  String shareUntil(String time);

  /// No description provided for @shareChoosePeople.
  ///
  /// In en, this message translates to:
  /// **'Who can see you?'**
  String get shareChoosePeople;

  /// No description provided for @shareConsentBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a Circle and the people allowed to see your current location. Your other Circle members will not receive it.'**
  String get shareConsentBody;

  /// No description provided for @shareNoMembers.
  ///
  /// In en, this message translates to:
  /// **'Invite someone to this Circle before sharing.'**
  String get shareNoMembers;

  /// No description provided for @shareAudience.
  ///
  /// In en, this message translates to:
  /// **'People with access'**
  String get shareAudience;

  /// No description provided for @shareRecipient.
  ///
  /// In en, this message translates to:
  /// **'Selected Circle member'**
  String get shareRecipient;

  /// No description provided for @shareDuration.
  ///
  /// In en, this message translates to:
  /// **'Automatically stop after'**
  String get shareDuration;

  /// No description provided for @shareMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String shareMinutes(int minutes);

  /// No description provided for @shareStart.
  ///
  /// In en, this message translates to:
  /// **'Agree & share my location'**
  String get shareStart;

  /// No description provided for @shareRetryConsent.
  ///
  /// In en, this message translates to:
  /// **'Retry the same consent'**
  String get shareRetryConsent;

  /// No description provided for @shareUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'The start result is unconfirmed. Retry uses the same people and expiry request; it cannot create a second share.'**
  String get shareUnconfirmed;

  /// No description provided for @shareUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating while this screen is open'**
  String get shareUpdating;

  /// No description provided for @sharePaused.
  ///
  /// In en, this message translates to:
  /// **'Location updates are paused'**
  String get sharePaused;

  /// No description provided for @shareNoHistory.
  ///
  /// In en, this message translates to:
  /// **'Only the latest fix is shared. Old locations disappear within 90 seconds.'**
  String get shareNoHistory;

  /// No description provided for @sharePause.
  ///
  /// In en, this message translates to:
  /// **'Pause updates'**
  String get sharePause;

  /// No description provided for @shareResume.
  ///
  /// In en, this message translates to:
  /// **'Agree & resume updates'**
  String get shareResume;

  /// No description provided for @shareStop.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get shareStop;

  /// No description provided for @shareStopBody.
  ///
  /// In en, this message translates to:
  /// **'Remove everyone\'s access to this trip location?'**
  String get shareStopBody;

  /// No description provided for @shareCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get shareCancel;

  /// No description provided for @shareRevoke.
  ///
  /// In en, this message translates to:
  /// **'Remove access'**
  String get shareRevoke;

  /// No description provided for @shareIncoming.
  ///
  /// In en, this message translates to:
  /// **'Shared with you'**
  String get shareIncoming;

  /// No description provided for @shareNoIncoming.
  ///
  /// In en, this message translates to:
  /// **'When someone chooses you, their trip appears here.'**
  String get shareNoIncoming;

  /// No description provided for @shareWaiting.
  ///
  /// In en, this message translates to:
  /// **'No current location. The person may be offline or have paused updates. This is not proof that they are safe or unsafe.'**
  String get shareWaiting;

  /// No description provided for @sharePosition.
  ///
  /// In en, this message translates to:
  /// **'Updated {time} · accuracy ±{metres} m'**
  String sharePosition(String time, int metres);

  /// No description provided for @shareClose.
  ///
  /// In en, this message translates to:
  /// **'Close location'**
  String get shareClose;

  /// No description provided for @shareDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline this share'**
  String get shareDecline;

  /// No description provided for @shareUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This share or recipient is no longer available. Refresh to check access.'**
  String get shareUnavailable;

  /// No description provided for @shareAlreadyActive.
  ///
  /// In en, this message translates to:
  /// **'A share is already active. Refresh to manage it.'**
  String get shareAlreadyActive;

  /// No description provided for @shareLocationProblem.
  ///
  /// In en, this message translates to:
  /// **'A fresh, precise Dhaka location is needed. Check location access and try resuming updates.'**
  String get shareLocationProblem;

  /// No description provided for @shareNetworkUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'The result could not be confirmed. If you changed sharing, refresh or explicitly retry that action. Location updates are paused after an upload error.'**
  String get shareNetworkUnconfirmed;

  /// No description provided for @shareBackground.
  ///
  /// In en, this message translates to:
  /// **'Keep sharing when locked'**
  String get shareBackground;

  /// No description provided for @shareBackgroundBody.
  ///
  /// In en, this message translates to:
  /// **'Allow precise location updates after leaving this screen or locking your phone, for the people listed below? The original end time stays the same. Android shows an ongoing notification with Stop sharing. Updates can be delayed by your connection or device settings.'**
  String get shareBackgroundBody;

  /// No description provided for @shareBackgroundAgree.
  ///
  /// In en, this message translates to:
  /// **'Agree & keep sharing'**
  String get shareBackgroundAgree;

  /// No description provided for @shareBackgroundOn.
  ///
  /// In en, this message translates to:
  /// **'Background location is on'**
  String get shareBackgroundOn;

  /// No description provided for @shareBackgroundPaused.
  ///
  /// In en, this message translates to:
  /// **'Background updates are paused'**
  String get shareBackgroundPaused;

  /// No description provided for @shareBackgroundHelp.
  ///
  /// In en, this message translates to:
  /// **'Your selected people can receive updates while the phone is locked. Pause here or use Stop sharing in the Android notification. Only the latest recent point is retained.'**
  String get shareBackgroundHelp;

  /// No description provided for @shareBackgroundUnknown.
  ///
  /// In en, this message translates to:
  /// **'Location status is unconfirmed. Check again before relying on updates. Stop sharing removes remote access once confirmed.'**
  String get shareBackgroundUnknown;

  /// No description provided for @shareBackgroundCheck.
  ///
  /// In en, this message translates to:
  /// **'Check sharing status'**
  String get shareBackgroundCheck;

  /// No description provided for @shareNotificationsRequired.
  ///
  /// In en, this message translates to:
  /// **'Allow Awaaz notifications and its Location sharing channel to keep a visible Stop sharing control. Then try again.'**
  String get shareNotificationsRequired;

  /// No description provided for @shareBackgroundUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Background sharing could not be confirmed. Refresh its status or stop this share before starting a new one.'**
  String get shareBackgroundUnavailable;

  /// No description provided for @shareLastUpload.
  ///
  /// In en, this message translates to:
  /// **'Last received by server: {time}'**
  String shareLastUpload(String time);

  /// No description provided for @sosHelp.
  ///
  /// In en, this message translates to:
  /// **'Help requests'**
  String get sosHelp;

  /// No description provided for @sosEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency services'**
  String get sosEmergency;

  /// No description provided for @sosDial.
  ///
  /// In en, this message translates to:
  /// **'Open dialer · 999'**
  String get sosDial;

  /// No description provided for @sosDialBody.
  ///
  /// In en, this message translates to:
  /// **'For immediate danger in Bangladesh, open the dialer to call 999.'**
  String get sosDialBody;

  /// No description provided for @sosDialFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the dialer. Dial 999 from your phone.'**
  String get sosDialFailed;

  /// No description provided for @sosInboxOnly.
  ///
  /// In en, this message translates to:
  /// **'In-app inbox only'**
  String get sosInboxOnly;

  /// No description provided for @sosDeliveryOff.
  ///
  /// In en, this message translates to:
  /// **'Push and SMS are not connected. Saving a request does not alert anyone outside the app. Contact someone directly for urgent help.'**
  String get sosDeliveryOff;

  /// No description provided for @sosCapabilityUnknown.
  ///
  /// In en, this message translates to:
  /// **'Checking available channels. Do not rely on this app for an emergency alert.'**
  String get sosCapabilityUnknown;

  /// No description provided for @sosReceive.
  ///
  /// In en, this message translates to:
  /// **'Receive help requests'**
  String get sosReceive;

  /// No description provided for @sosReceiveBody.
  ///
  /// In en, this message translates to:
  /// **'Allow Circle members to choose you as a recipient. Opening a request does not tell them you have seen it.'**
  String get sosReceiveBody;

  /// No description provided for @sosOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get sosOn;

  /// No description provided for @sosOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get sosOff;

  /// No description provided for @sosReviewSetting.
  ///
  /// In en, this message translates to:
  /// **'Review receiving setting'**
  String get sosReviewSetting;

  /// No description provided for @sosSettingUnknown.
  ///
  /// In en, this message translates to:
  /// **'Your last change is unconfirmed. Review the current setting and confirm your choice.'**
  String get sosSettingUnknown;

  /// No description provided for @sosSave.
  ///
  /// In en, this message translates to:
  /// **'Save help request'**
  String get sosSave;

  /// No description provided for @sosSelect.
  ///
  /// In en, this message translates to:
  /// **'Choose who can help'**
  String get sosSelect;

  /// No description provided for @sosSelectBody.
  ///
  /// In en, this message translates to:
  /// **'Only opted-in members of this Circle are listed. Choose up to 10 people.'**
  String get sosSelectBody;

  /// No description provided for @sosNoContacts.
  ///
  /// In en, this message translates to:
  /// **'No eligible recipients. Ask a Circle member to enable receiving help requests.'**
  String get sosNoContacts;

  /// No description provided for @sosLocation.
  ///
  /// In en, this message translates to:
  /// **'Include my current location'**
  String get sosLocation;

  /// No description provided for @sosLocationBody.
  ///
  /// In en, this message translates to:
  /// **'Updates run only while this screen is open. Leaving or locking the phone pauses them. Only the latest point is shared, for up to 90 seconds.'**
  String get sosLocationBody;

  /// No description provided for @sosReviewStart.
  ///
  /// In en, this message translates to:
  /// **'Review your help request'**
  String get sosReviewStart;

  /// No description provided for @sosStartBody.
  ///
  /// In en, this message translates to:
  /// **'These people can open your request for one hour. No sound will play. This does not contact emergency services.'**
  String get sosStartBody;

  /// No description provided for @sosSaved.
  ///
  /// In en, this message translates to:
  /// **'Request saved'**
  String get sosSaved;

  /// No description provided for @sosActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get sosActive;

  /// No description provided for @sosEnded.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get sosEnded;

  /// No description provided for @sosCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get sosCancelled;

  /// No description provided for @sosExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get sosExpired;

  /// No description provided for @sosEnd.
  ///
  /// In en, this message translates to:
  /// **'Resolve request'**
  String get sosEnd;

  /// No description provided for @sosCancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get sosCancelRequest;

  /// No description provided for @sosEndBody.
  ///
  /// In en, this message translates to:
  /// **'End this request and remove access to its location? Recipients may still have seen earlier information.'**
  String get sosEndBody;

  /// No description provided for @sosRecipients.
  ///
  /// In en, this message translates to:
  /// **'People you chose'**
  String get sosRecipients;

  /// No description provided for @sosNoResponse.
  ///
  /// In en, this message translates to:
  /// **'No response yet'**
  String get sosNoResponse;

  /// No description provided for @sosRevoked.
  ///
  /// In en, this message translates to:
  /// **'Access removed'**
  String get sosRevoked;

  /// No description provided for @sosSeen.
  ///
  /// In en, this message translates to:
  /// **'Seen'**
  String get sosSeen;

  /// No description provided for @sosContacting.
  ///
  /// In en, this message translates to:
  /// **'Contacting you'**
  String get sosContacting;

  /// No description provided for @sosHelping.
  ///
  /// In en, this message translates to:
  /// **'Helping'**
  String get sosHelping;

  /// No description provided for @sosUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unable to help'**
  String get sosUnavailable;

  /// No description provided for @sosNotification.
  ///
  /// In en, this message translates to:
  /// **'Notification status'**
  String get sosNotification;

  /// No description provided for @sosQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued; not sent'**
  String get sosQueued;

  /// No description provided for @sosSending.
  ///
  /// In en, this message translates to:
  /// **'Sending; unconfirmed'**
  String get sosSending;

  /// No description provided for @sosAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted by provider; device delivery unconfirmed'**
  String get sosAccepted;

  /// No description provided for @sosFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get sosFailed;

  /// No description provided for @sosUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unconfirmed'**
  String get sosUnknown;

  /// No description provided for @sosPending.
  ///
  /// In en, this message translates to:
  /// **'Save result unconfirmed'**
  String get sosPending;

  /// No description provided for @sosPendingBody.
  ///
  /// In en, this message translates to:
  /// **'The server may have saved this request. Check its receipt, retry the same people and choices, or withdraw it. No new request will be created by a retry.'**
  String get sosPendingBody;

  /// No description provided for @sosRetry.
  ///
  /// In en, this message translates to:
  /// **'Review same request'**
  String get sosRetry;

  /// No description provided for @sosWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw request'**
  String get sosWithdraw;

  /// No description provided for @sosWithdrawBody.
  ///
  /// In en, this message translates to:
  /// **'Prevent this request from starting, or cancel it if already saved? This also removes access to its location once confirmed.'**
  String get sosWithdrawBody;

  /// No description provided for @sosIncoming.
  ///
  /// In en, this message translates to:
  /// **'Requests for you'**
  String get sosIncoming;

  /// No description provided for @sosInboxEmpty.
  ///
  /// In en, this message translates to:
  /// **'Help requests from your Circle will appear here when someone chooses you.'**
  String get sosInboxEmpty;

  /// No description provided for @sosRespond.
  ///
  /// In en, this message translates to:
  /// **'Send a response'**
  String get sosRespond;

  /// No description provided for @sosRespondBody.
  ///
  /// In en, this message translates to:
  /// **'This explicitly shares your selected response with the requester. It does not end their request.'**
  String get sosRespondBody;

  /// No description provided for @sosDecline.
  ///
  /// In en, this message translates to:
  /// **'Remove my access'**
  String get sosDecline;

  /// No description provided for @sosDeclineBody.
  ///
  /// In en, this message translates to:
  /// **'Remove yourself from this request? You will no longer see its location.'**
  String get sosDeclineBody;

  /// No description provided for @sosNotice.
  ///
  /// In en, this message translates to:
  /// **'Change confirmed by server'**
  String get sosNotice;

  /// No description provided for @sosNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not confirm the result. Refresh to check the server before taking further action.'**
  String get sosNetwork;

  /// No description provided for @sosConflict.
  ///
  /// In en, this message translates to:
  /// **'The request or setting changed. Refresh and review again.'**
  String get sosConflict;

  /// No description provided for @sosStorage.
  ///
  /// In en, this message translates to:
  /// **'Private request storage is unavailable. No new request can start until it is restored.'**
  String get sosStorage;

  /// No description provided for @sosLocationPaused.
  ///
  /// In en, this message translates to:
  /// **'Location updates paused'**
  String get sosLocationPaused;

  /// No description provided for @sosLocationUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating location on this screen'**
  String get sosLocationUpdating;

  /// No description provided for @sosResumeBody.
  ///
  /// In en, this message translates to:
  /// **'Resume sharing your current location with the people listed on this request, while this screen is open?'**
  String get sosResumeBody;

  /// No description provided for @sosTerminalBody.
  ///
  /// In en, this message translates to:
  /// **'This request has ended. Its location is no longer available.'**
  String get sosTerminalBody;

  /// No description provided for @sosFreshOnly.
  ///
  /// In en, this message translates to:
  /// **'A missing location does not indicate whether this person is safe. Contact them directly.'**
  String get sosFreshOnly;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bn', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
