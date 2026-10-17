// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get clearSearch => 'Clear search';

  @override
  String get previewDestinations => 'Preview destinations';

  @override
  String get explore => 'Explore';

  @override
  String get community => 'Community';

  @override
  String get circle => 'Circle';

  @override
  String get demo => 'DEMO · No live tracking or messages';

  @override
  String get homeTitle => 'Where to today?';

  @override
  String get homeSubtitle => 'A little more confidence, wherever you go.';

  @override
  String get whereTo => 'Where are you heading?';

  @override
  String get searchHint => 'Search demo destinations';

  @override
  String get chooseDestination => 'Choose a destination';

  @override
  String get plan => 'Plan a journey';

  @override
  String get schematic => 'Dhaka · schematic map';

  @override
  String get fixtureMap => 'Illustrative route, not navigation';

  @override
  String get origin => 'Farmgate';

  @override
  String get car => 'Car';

  @override
  String get walk => 'Walk';

  @override
  String get aroundYou => 'Around you';

  @override
  String get coverageHint =>
      'Community signals help you choose. Streets without reports remain unknown.';

  @override
  String get routesTitle => 'Choose your route';

  @override
  String get lowerRisk => 'Lower reported risk';

  @override
  String get fastest => 'Fastest';

  @override
  String get limitedCoverage => 'Limited coverage · No safety guarantee';

  @override
  String get routeNote =>
      'ETAs and evidence coverage are illustrative. Reports cannot predict every incident.';

  @override
  String get start => 'Start demo journey';

  @override
  String get loadingRoutes => 'Comparing demo routes…';

  @override
  String get routeError => 'Routes could not be loaded';

  @override
  String get retry => 'Try again';

  @override
  String get offline => 'Offline preview · Local drafts still work';

  @override
  String get offlineNote =>
      'A new route needs a connection. Restore the normal demo scenario to try again.';

  @override
  String get errorNote =>
      'Change the demo scenario or retry to explore this state.';

  @override
  String get journeyTitle => 'Journey in progress';

  @override
  String get monitoringDemo => 'Simulated journey · Location sharing off';

  @override
  String get baseline =>
      'Your chosen route is the monitoring baseline. Background tracking is not connected yet.';

  @override
  String get previewDeviation => 'Preview a route deviation';

  @override
  String get endJourney => 'End journey';

  @override
  String get deviationTitle => 'Your route has changed';

  @override
  String get deviationSubtitle => 'A check-in before any escalation.';

  @override
  String get detourQuestion => 'Are you comfortable with this detour?';

  @override
  String get detourBody =>
      'A detour can be normal. Confirm it if you expected this change. This example uses simulated GPS.';

  @override
  String get acceptDetour => 'I expected this detour';

  @override
  String get keepRoute => 'Keep original route';

  @override
  String get noAutomaticMessage =>
      'No contact is notified automatically in this demo.';

  @override
  String get openSos => 'Open SOS';

  @override
  String get sosTitle => 'Request help';

  @override
  String get sosBody =>
      'Preview only. No emergency service is connected and no message will be sent.';

  @override
  String get sosConfirm => 'Confirm';

  @override
  String get sosReceipt => 'Demo SOS recorded. No message was sent.';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get communityTitle => 'Your city, together.';

  @override
  String get communitySubtitle =>
      'Report events. Help others make informed choices.';

  @override
  String get reportIncident => 'Report an incident';

  @override
  String get unreviewed => 'Unreviewed · Demo report';

  @override
  String get reviewed => 'Reviewed · Demo report';

  @override
  String get verificationNote =>
      'Verified account ≠ verified report. These are illustrative reports.';

  @override
  String get construction =>
      'Construction blocks part of the footpath near the crossing.';

  @override
  String get lights => 'Street lights are out near the crossing.';

  @override
  String get noReports => 'No reports in this preview';

  @override
  String get unknown => 'No reports means unknown, not safe.';

  @override
  String get reportTitle => 'What happened?';

  @override
  String get reportSubtitle => 'Describe the event without identifying people.';

  @override
  String get category => 'Category';

  @override
  String get place => 'Place';

  @override
  String get description => 'Description';

  @override
  String get privacyCopy =>
      'Use demo text only. Do not include faces, names, phone numbers or accusations. This draft stays on this device.';

  @override
  String get privacyConsent => 'I understand this is a private demo draft.';

  @override
  String get saveDraft => 'Save demo draft';

  @override
  String get savedDraft => 'Saved on this device. Not published.';

  @override
  String get drafts => 'Your local drafts';

  @override
  String get deleteDrafts => 'Delete local drafts';

  @override
  String get deleteConfirm => 'Delete all demo drafts from this device?';

  @override
  String get delete => 'Delete';

  @override
  String get localOnly => 'Private · This device only';

  @override
  String get validation =>
      'Enter a place and a description of 10–700 characters.';

  @override
  String get storageError =>
      'Could not read or save local drafts. Please try again.';

  @override
  String get circleTitle => 'Your people, close by';

  @override
  String get circleSubtitle => 'Sharing is always your choice.';

  @override
  String get friend => 'Friend · Demo contact';

  @override
  String get family => 'Family · Demo contact';

  @override
  String get privateTitle => 'Private by default';

  @override
  String get privateBody =>
      'No sharing is active. Production invitations will require mutual consent. These contacts are fixtures.';

  @override
  String get demoScenarios => 'Demo scenarios';

  @override
  String get normal => 'Normal';

  @override
  String get simulateOffline => 'Offline';

  @override
  String get simulateError => 'Route error';

  @override
  String get emptyReports => 'Empty reports';

  @override
  String get back => 'Back';

  @override
  String get obstruction => 'Road obstruction';

  @override
  String get lighting => 'Street lighting issue';

  @override
  String get theft => 'Theft incident';

  @override
  String get harassment => 'Harassment';

  @override
  String get accident => 'Accident';

  @override
  String get other => 'Other event';

  @override
  String get noDestinations => 'No demo destinations match';

  @override
  String metric(String minutes, String km) {
    return '$minutes min · $km km';
  }

  @override
  String get dhakaPilot => 'DHAKA PILOT';

  @override
  String get plannerLabel => 'PLAN YOUR WAY';

  @override
  String get savedPlaces => 'Quick destinations';

  @override
  String get savedLake => 'Lake';

  @override
  String get savedCampus => 'Campus';

  @override
  String get savedMetro => 'Metro';

  @override
  String get selectedDestination => 'Selected destination';

  @override
  String get resetMap => 'Reset map view';

  @override
  String get zoomMap => 'Zoom in';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String get mapDemoLabel => 'Illustrative map';

  @override
  String get mapSignals => 'Demo road reports';

  @override
  String get routePreview => 'ROUTE PREVIEW';

  @override
  String get journeyOverview => 'JOURNEY OVERVIEW';

  @override
  String get travelTime => 'Travel time';

  @override
  String get minutesShort => 'min';

  @override
  String get distanceShort => 'km';

  @override
  String get routeChoiceNote => 'Choose what works for you.';

  @override
  String get fromLabel => 'From';

  @override
  String get toLabel => 'To';

  @override
  String get coverageLabel => 'Evidence coverage';

  @override
  String get extraTime => 'A little longer, fewer reported concerns.';

  @override
  String get fastestNote => 'Less travel time on the demo network.';

  @override
  String get allReports => 'All reports';

  @override
  String get communitySignals => 'Around Dhaka';

  @override
  String get sharingOff => 'Sharing off';

  @override
  String get yourCircle => 'YOUR CIRCLE';

  @override
  String get circlePeople => 'People you trust';

  @override
  String get journeyActions => 'Journey controls';

  @override
  String get checkInLabel => 'ROUTE CHECK-IN';

  @override
  String get reportBasics => 'Event details';

  @override
  String get reportPrivacyTitle => 'Private until you decide';

  @override
  String get reportPrivacyCaption => 'This draft stays on your device.';

  @override
  String get accountOpen => 'Account';

  @override
  String get accountTitle => 'Your Awaaz account';

  @override
  String get accountSetup => 'Accounts are not connected in this preview yet.';

  @override
  String get accountSetupBody =>
      'You can still explore demo journeys and private demo drafts.';

  @override
  String get accountSignIn => 'Continue with your phone';

  @override
  String get accountSignInBody =>
      'A code confirms control of your phone. It does not verify reports or enable location sharing.';

  @override
  String get accountPhone => 'Bangladesh mobile number';

  @override
  String get accountSendCode => 'Send a code';

  @override
  String get accountCode => 'Verification code';

  @override
  String get accountVerify => 'Verify and continue';

  @override
  String get accountChangePhone => 'Use another number';

  @override
  String get accountName => 'Your display name';

  @override
  String get accountAdult => 'I am 18 or older.';

  @override
  String get accountSaveProfile => 'Save profile';

  @override
  String get accountProfile => 'Profile';

  @override
  String get accountCircles => 'Trusted Circles';

  @override
  String get accountReports => 'My reports';

  @override
  String get accountSignOut => 'Sign out on this device';

  @override
  String get accountPhoneVerified => 'Phone confirmed';

  @override
  String get accountPhoneVerify =>
      'Confirm your phone before submitting a report.';

  @override
  String get accountConnectionCode => 'Your connection code';

  @override
  String get accountCopy => 'Copy';

  @override
  String get accountCopied => 'Copied';

  @override
  String get accountNewCircle => 'Circle name';

  @override
  String get accountCreateCircle => 'Create a Circle';

  @override
  String get accountNoCircles => 'No Circles yet. Invite someone you trust.';

  @override
  String get accountRecipient => 'Their connection code';

  @override
  String get accountInvite => 'Create an invitation';

  @override
  String get accountInviteCode => 'Share this code with the invited person.';

  @override
  String get accountInvitations => 'Invitations for you';

  @override
  String get accountAccept => 'Accept with code';

  @override
  String get accountDecline => 'Decline';

  @override
  String get accountInviteSecret => 'Invitation code';

  @override
  String get accountMembershipPrivacy =>
      'Joining a Circle does not share your location.';

  @override
  String get accountRemove => 'Remove';

  @override
  String get accountLeave => 'Leave Circle';

  @override
  String get accountCloseCircle => 'Close Circle';

  @override
  String get accountConfirm => 'Confirm this change?';

  @override
  String get accountNoReports => 'You have no submitted reports.';

  @override
  String get accountPending => 'Pending review · Private';

  @override
  String get accountReviewed => 'Reviewed';

  @override
  String get accountRejected => 'Rejected · Private';

  @override
  String get accountWithdraw => 'Withdraw report';

  @override
  String get accountWithdrawalBody =>
      'This removes your submitted text and location, and its linked public event. A retry will not restore them.';

  @override
  String get accountMoreReports => 'Load more reports';

  @override
  String get accountPublished => 'Published road reports';

  @override
  String get accountManage => 'Manage my account and Circles';

  @override
  String get accountEmptyEvents =>
      'No published reports. Road conditions remain unknown.';

  @override
  String get accountPhoneInvalid => 'Enter a valid Bangladesh mobile number.';

  @override
  String get accountCodeInvalid => 'Check the code and try again.';

  @override
  String get accountRateLimit =>
      'Too many attempts. Please wait before trying again.';

  @override
  String get accountRequestFailed =>
      'We could not complete this request. Check the details and retry.';

  @override
  String get accountNetwork =>
      'Account services could not be reached. Check your connection and retry.';

  @override
  String get accountInviteUnavailable =>
      'This invitation is no longer available. Ask for a new one.';

  @override
  String get accountInviteExists =>
      'An invitation is already pending for this person.';

  @override
  String get accountAlreadyJoined => 'This person is already a member.';

  @override
  String get accountLimit =>
      'This Circle or account has reached its current limit.';

  @override
  String get accountOwnerMustClose =>
      'The owner must close the Circle rather than leave it.';

  @override
  String get accountLogoutPending =>
      'Signed out locally. Server sign-out could not be confirmed.';

  @override
  String get accountPreviewStatus =>
      'Preview routes · No live tracking or alerts';

  @override
  String get accountSavedWrites => 'Saved requests';

  @override
  String get accountSavedWritesBody =>
      'Stored privately on this device. Nothing resends automatically. A request may already have arrived; retry uses the same request ID.';

  @override
  String get accountRemoveRetry => 'Remove saved request';

  @override
  String get accountRemoveRetryBody =>
      'Remove this device\'s saved request? This does not undo anything already received by the server. Check your Circles or report history before submitting again.';

  @override
  String get accountSavedCircle => 'Create Circle';

  @override
  String get accountSavedInvite => 'Circle invitation';

  @override
  String get accountSavedReport => 'Road report';

  @override
  String get accountSavedLocation => 'Reported location';

  @override
  String get accountRetryOld =>
      'This report is over 72 hours old. Check your report history; its original observation time will not be changed.';

  @override
  String get accountStorage =>
      'Private storage is unavailable. No replacement request will be sent. Retry after checking device storage.';

  @override
  String get accountRetryCleanup =>
      'The server received the request, but its saved copy could not be cleared. Retrying this copy uses the same ID.';

  @override
  String get accountRetryLimit =>
      'Saved requests have reached the device limit. Review them before adding more.';

  @override
  String get accountWithdrawnReceipt =>
      'This report was already withdrawn. Retrying did not restore it.';

  @override
  String get accountCheckStatus => 'Check status';

  @override
  String get accountReportNotReceived =>
      'No server receipt was found. This report is too old to send; check history before removing its saved request.';

  @override
  String get composeOpen => 'Submit a road report';

  @override
  String get composeTitle => 'Report a road condition';

  @override
  String get composeBody =>
      'Report what you observed here, just now. Your report stays private until reviewed. Avoid names, faces or accusations about individuals.';

  @override
  String get composeLocation => 'Use my current location';

  @override
  String get composeLocationPurpose =>
      'Location is collected only when you tap this button, to place this report on the right road. It is not shared with your Circle.';

  @override
  String get composeLocated => 'Current location captured';

  @override
  String get composePrecision => 'Estimated accuracy';

  @override
  String get composeConsent =>
      'I observed this condition here and agree to submit this text and location for review.';

  @override
  String get composeSubmit => 'Submit privately for review';

  @override
  String get composeSuccess => 'Report received for private review.';

  @override
  String get composeSaved => 'View saved requests and report history';

  @override
  String get composeTestLocation => 'Synthetic test location';

  @override
  String get composePermission =>
      'Location access was declined. You can continue using the rest of Awaaz.';

  @override
  String get composePermanent =>
      'Location access is disabled for Awaaz. Enable it in app settings if you want to place this report.';

  @override
  String get composeDisabled =>
      'Location services are off. Turn them on, then capture your location again.';

  @override
  String get composeApproximate =>
      'Approximate location cannot identify the road reliably. Choose precise access in app settings to submit this report.';

  @override
  String get composeInaccurate =>
      'This location is too uncertain to identify the road. Try again with a clearer GPS signal.';

  @override
  String get composeStale =>
      'Capture your current location again before submitting.';

  @override
  String get composeMocked =>
      'A simulated location cannot be used for a live report.';

  @override
  String get composeOutside =>
      'Road reporting is currently available within the Dhaka pilot area.';

  @override
  String get composeUnavailable =>
      'A current location could not be captured. Try again when location services are available.';

  @override
  String get composeAppSettings => 'Open app settings';

  @override
  String get composeLocationSettings => 'Open location settings';

  @override
  String get nativeActive => 'On-device route checks active';

  @override
  String get nativeOff => 'Background route checks off';

  @override
  String get nativeStatusUnknown => 'Monitoring status unavailable';

  @override
  String get nativeStatusUnknownBody =>
      'We could not confirm whether background route checks are running. Try again to check the current status before relying on alerts.';

  @override
  String get nativeCheckIn => 'Is this detour expected?';

  @override
  String get nativeInterrupted => 'Journey monitoring was interrupted';

  @override
  String get nativeUncertain => 'Waiting for reliable location';

  @override
  String get nativePrivate =>
      'Checks run on this device. Circle sharing and contact escalation are off. You can stop from the ongoing notification.';

  @override
  String get nativeArmBody =>
      'Starting this journey will request location and notification access, and show an ongoing monitoring notification.';

  @override
  String get nativeNoCorridor =>
      'This preview route has no approved street corridor. It cannot arm background GPS checks.';

  @override
  String get nativeFixture =>
      'Synthetic corridor test · no sharing or contact delivery';

  @override
  String get nativeNotifications =>
      'Enable journey notifications before arming background alerts.';

  @override
  String get nativeLocation =>
      'Precise foreground location access is required to start monitoring.';

  @override
  String get nativeVisible =>
      'Open Awaaz before starting or changing journey monitoring.';

  @override
  String get nativeUnsupported =>
      'Native journey monitoring is currently available on Android.';

  @override
  String get nativeFailure =>
      'Monitoring could not complete this action. Check its status before relying on route alerts.';

  @override
  String get nativeKeepWatching => 'Keep watching this route';

  @override
  String get nativeStop => 'Stop monitoring';

  @override
  String get mapUseLocation => 'Show my location';

  @override
  String get mapTraffic => 'Traffic';

  @override
  String get mapUnavailable =>
      'The map could not respond. Check your connection and try again.';

  @override
  String get mapLocating => 'Finding your location';

  @override
  String get mapLocationUnavailable =>
      'A reliable current location could not be found. Try again with a clearer GPS signal.';

  @override
  String get mapLocationDenied =>
      'Location access was declined. You can still browse the map.';

  @override
  String get mapMyLocation => 'My location';

  @override
  String get mapLocationPurpose =>
      'Show your location on Google Maps while this map is visible. Google processes map and location data to provide this view. This does not start a journey or share your location with your Circle.';

  @override
  String get mapPreviewStatus =>
      'Google Maps · Journeys and sharing are previews';

  @override
  String get mapStopLocation => 'Stop showing my location';

  @override
  String get communityLoading => 'Loading road reports';

  @override
  String get circleMember => 'Joined Circle';

  @override
  String get communityPublished => 'Published road report';

  @override
  String get communityObserved => 'Observed';

  @override
  String get communityFinishSetup => 'Finish account setup';

  @override
  String get communityFeedIntro => 'Reported road conditions in Dhaka.';

  @override
  String get communitySignIn =>
      'Sign in and complete your profile to read published road reports and manage your submissions.';

  @override
  String get circleSignIn =>
      'Sign in to create a Circle, review invitations and choose who joins.';

  @override
  String get circleOwner => 'You manage this Circle';

  @override
  String get communityPublishedNote =>
      'Published reports expire. They describe observations, not a guarantee of safety.';

  @override
  String get journeyPlannedEstimate =>
      'Planned estimate; not live remaining time';

  @override
  String get journeyPreviewChecks =>
      'Preview journey. Background GPS checks and Circle sharing are off.';

  @override
  String get journeyEnding => 'Stopping monitoring…';

  @override
  String get journeyNativeDetour =>
      'A detour can be normal. Your chosen route stays selected; no contacts are notified.';

  @override
  String get journeyArmTitle => 'Start background route checks?';

  @override
  String get journeyStartNative => 'Start monitoring';

  @override
  String get journeyStarting => 'Starting journey…';

  @override
  String get journeyNativeStatus =>
      'On-device checks · Sharing and contact delivery off';

  @override
  String get geoPinnedDestination => 'Pinned destination';

  @override
  String get geoRoutesTitle => 'Your street route';

  @override
  String get geoCurrentOrigin => 'Current location';

  @override
  String get geoStatus => 'Street routing · Safety evidence unknown';

  @override
  String get geoUnknownSafety =>
      'Safety coverage unknown. This is not a safety-ranked route.';

  @override
  String get geoEstimate =>
      'Static OSM estimate; live traffic is not included.';

  @override
  String get geoMapUnavailable =>
      'Geographic map display is unavailable. You can enter a destination\'s coordinates in the Dhaka pilot area.';

  @override
  String get geoChoosePin => 'Choose a road or entrance';

  @override
  String get geoPinHint =>
      'Search for a place or hold the map to choose an arrival point in Dhaka.';

  @override
  String get geoUsePin => 'Use this destination';

  @override
  String get geoLatitude => 'Latitude';

  @override
  String get geoLongitude => 'Longitude';

  @override
  String get geoPlanConsentTitle => 'Plan from your current location?';

  @override
  String get geoPlanConsentBody =>
      'Use one fresh, precise location fix and send it with your destination to the Awaaz routing server. Google processes map data for the map view. Planning does not start background checks, save a trip history or share your location with your Circle.';

  @override
  String get geoUseOrigin => 'Use current location';

  @override
  String get geoLoading =>
      'Finding a fresh origin and planning a street route…';

  @override
  String get geoRoutingUnavailable =>
      'Street routing is unavailable. Check the connection and try again. No demo route has been substituted.';

  @override
  String get geoSnapTooFar =>
      'A nearby routable road could not be found. Choose a road or entrance closer to your destination, or retry with a clearer origin fix.';

  @override
  String get geoAlreadyThere =>
      'You are already close to this destination. Choose another destination to plan a route.';

  @override
  String get geoOutside => 'This route is outside the Dhaka pilot area.';

  @override
  String get geoEnableLocation =>
      'Turn on location services to plan from your current position.';

  @override
  String get geoPlanningCanceled =>
      'Planning was cancelled. Retry explicitly to acquire a fresh location.';

  @override
  String get geoExpired =>
      'This route plan expired. Plan again before starting background checks.';

  @override
  String get geoMockMonitoring =>
      'Test GPS can preview routes, but cannot arm production background checks. Use a physical phone with reliable location.';

  @override
  String get geoReportedChoice => 'Fewer reported issues';

  @override
  String get geoTestDisclosure => 'Test reports · Safety unknown';

  @override
  String get geoExperimentalDisclosure => 'Experimental · Safety unknown';

  @override
  String geoReportCoverage(int percent) {
    return 'Reviewed observations on $percent% of this route';
  }

  @override
  String get geoReportedNote =>
      'Experimental comparison using reviewed reports. Unreported streets remain unknown; neither option guarantees safety.';

  @override
  String get geoSyntheticReports =>
      'Test reports · These observations are synthetic, not live Dhaka incidents.';

  @override
  String get placeSearchTitle => 'Search Dhaka';

  @override
  String get placeSearchHint => 'Search places or roads';

  @override
  String get placeSearchPrivacy =>
      'Search words are sent to Awaaz. Results use imported OpenStreetMap data and may be incomplete.';

  @override
  String get placeStart =>
      'Enter at least two characters to find a place or road.';

  @override
  String get placeNoResults =>
      'No matching imported places. Try another name or choose a pin on the map.';

  @override
  String get placeUnavailable =>
      'Place search is unavailable. Retry or choose a pin on the map.';

  @override
  String get placeClear => 'Clear search';

  @override
  String get placePaused =>
      'Search paused while you were away. Tap Retry to search again.';

  @override
  String get placeReviewPin =>
      'Check this arrival point. Hold the map to move it to the road or entrance you want.';

  @override
  String get placeRoad => 'Road';

  @override
  String get placeEducation => 'Education';

  @override
  String get placeHealth => 'Health facility';

  @override
  String get placeTransit => 'Transit stop';

  @override
  String get placeShop => 'Shop';

  @override
  String get placeArea => 'Area';

  @override
  String get placePublic => 'Mapped place';

  @override
  String get routeChangeTitle => 'Change route';

  @override
  String get routeChangeBody =>
      'Find routes from your current location to the same destination. Looking up or selecting a route does not change the monitoring baseline.';

  @override
  String get routeChangeCurrent => 'Original monitored route';

  @override
  String get routeChangeFind => 'Find updated routes';

  @override
  String get routeChangeConfirm => 'Replace monitored route?';

  @override
  String get routeChangeConfirmBody =>
      'The selected route will become the new monitoring baseline. Route checks restart on that corridor only after Android confirms the change.';

  @override
  String get routeChangeUse => 'Use this route';

  @override
  String get routeChangeUnconfirmed =>
      'The route change is not confirmed. Check monitoring status before trying again.';

  @override
  String get routeChangeNotApplied =>
      'Android confirms the original route is still monitored. You can retry or return to your journey.';

  @override
  String get routeChangeUnavailable =>
      'The journey or monitored route has changed. Return to the journey before finding another route.';

  @override
  String get routeChangeCheck => 'Check monitoring status';

  @override
  String get routeChangeApplied => 'Monitored route updated';

  @override
  String get routeChangeExpired =>
      'This route plan expired. Find updated routes before changing the monitoring baseline.';

  @override
  String get blocksTitle => 'Blocked accounts';

  @override
  String get blocksBody =>
      'Manage who can join a Circle with you. Unblocking never restores membership or an old invitation.';

  @override
  String get blocksEmpty => 'No blocked accounts';

  @override
  String get blocksEmptyBody =>
      'You can block a member from their Circle or block the sender of an invitation.';

  @override
  String get blockAccount => 'Block account';

  @override
  String get unblockAccount => 'Unblock account';

  @override
  String get blockConfirmBody =>
      'You will no longer share a Circle. They will be removed from Circles you own; you will leave other Circles you share. Conflicting invitations will be revoked.';

  @override
  String get unblockConfirmBody =>
      'This removes your block. It does not rejoin a Circle or restore invitations. Connecting again requires a new invitation and acceptance.';

  @override
  String get blockedUnknownName => 'Blocked account';

  @override
  String get blocksLoad => 'Load blocked accounts';

  @override
  String get blocksMore => 'Load more';

  @override
  String get blockUnconfirmedTitle => 'Contact change not confirmed';

  @override
  String get blockUnconfirmedBody =>
      'Circle details are hidden while the result is uncertain. Check the current decision or explicitly retry the same request. No request is resent automatically.';

  @override
  String get blockCheck => 'Check decision';

  @override
  String get blockRetry => 'Retry this decision';

  @override
  String get blockChanged =>
      'This decision changed elsewhere. Check it again before making another change.';

  @override
  String get blockLimit => 'Your blocked-account limit has been reached.';

  @override
  String get blockVersionLimit =>
      'This decision cannot be changed further. Contact support.';

  @override
  String get blockUnavailable =>
      'This account or decision is no longer available.';

  @override
  String get shareTitle => 'Trip sharing';

  @override
  String get shareHeadline => 'Let your people know where you are.';

  @override
  String get shareForeground =>
      'Location updates run while this screen is open. Leaving the screen or locking your phone pauses updates. Sharing ends at the chosen time.';

  @override
  String get shareActive => 'Sharing is on';

  @override
  String shareUntil(String time) {
    return 'Until $time';
  }

  @override
  String get shareChoosePeople => 'Who can see you?';

  @override
  String get shareConsentBody =>
      'Choose a Circle and the people allowed to see your current location. Your other Circle members will not receive it.';

  @override
  String get shareNoMembers => 'Invite someone to this Circle before sharing.';

  @override
  String get shareAudience => 'People with access';

  @override
  String get shareRecipient => 'Selected Circle member';

  @override
  String get shareDuration => 'Automatically stop after';

  @override
  String shareMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get shareStart => 'Agree & share my location';

  @override
  String get shareRetryConsent => 'Retry the same consent';

  @override
  String get shareUnconfirmed =>
      'The start result is unconfirmed. Retry uses the same people and expiry request; it cannot create a second share.';

  @override
  String get shareUpdating => 'Updating while this screen is open';

  @override
  String get sharePaused => 'Location updates are paused';

  @override
  String get shareNoHistory =>
      'Only the latest fix is shared. Old locations disappear within 90 seconds.';

  @override
  String get sharePause => 'Pause updates';

  @override
  String get shareResume => 'Agree & resume updates';

  @override
  String get shareStop => 'Stop sharing';

  @override
  String get shareStopBody =>
      'Remove everyone\'s access to this trip location?';

  @override
  String get shareCancel => 'Cancel';

  @override
  String get shareRevoke => 'Remove access';

  @override
  String get shareIncoming => 'Shared with you';

  @override
  String get shareNoIncoming =>
      'When someone chooses you, their trip appears here.';

  @override
  String get shareWaiting =>
      'No current location. The person may be offline or have paused updates. This is not proof that they are safe or unsafe.';

  @override
  String sharePosition(String time, int metres) {
    return 'Updated $time · accuracy ±$metres m';
  }

  @override
  String get shareClose => 'Close location';

  @override
  String get shareDecline => 'Decline this share';

  @override
  String get shareUnavailable =>
      'This share or recipient is no longer available. Refresh to check access.';

  @override
  String get shareAlreadyActive =>
      'A share is already active. Refresh to manage it.';

  @override
  String get shareLocationProblem =>
      'A fresh, precise Dhaka location is needed. Check location access and try resuming updates.';

  @override
  String get shareNetworkUnconfirmed =>
      'The result could not be confirmed. If you changed sharing, refresh or explicitly retry that action. Location updates are paused after an upload error.';

  @override
  String get shareBackground => 'Keep sharing when locked';

  @override
  String get shareBackgroundBody =>
      'Allow precise location updates after leaving this screen or locking your phone, for the people listed below? The original end time stays the same. Android shows an ongoing notification with Stop sharing. Updates can be delayed by your connection or device settings.';

  @override
  String get shareBackgroundAgree => 'Agree & keep sharing';

  @override
  String get shareBackgroundOn => 'Background location is on';

  @override
  String get shareBackgroundPaused => 'Background updates are paused';

  @override
  String get shareBackgroundHelp =>
      'Your selected people can receive updates while the phone is locked. Pause here or use Stop sharing in the Android notification. Only the latest recent point is retained.';

  @override
  String get shareBackgroundUnknown =>
      'Location status is unconfirmed. Check again before relying on updates. Stop sharing removes remote access once confirmed.';

  @override
  String get shareBackgroundCheck => 'Check sharing status';

  @override
  String get shareNotificationsRequired =>
      'Allow Awaaz notifications and its Location sharing channel to keep a visible Stop sharing control. Then try again.';

  @override
  String get shareBackgroundUnavailable =>
      'Background sharing could not be confirmed. Refresh its status or stop this share before starting a new one.';

  @override
  String shareLastUpload(String time) {
    return 'Last received by server: $time';
  }

  @override
  String get sosHelp => 'Help requests';

  @override
  String get sosEmergency => 'Emergency services';

  @override
  String get sosDial => 'Open dialer · 999';

  @override
  String get sosDialBody =>
      'For immediate danger in Bangladesh, open the dialer to call 999.';

  @override
  String get sosDialFailed =>
      'Could not open the dialer. Dial 999 from your phone.';

  @override
  String get sosInboxOnly => 'In-app inbox only';

  @override
  String get sosDeliveryOff =>
      'Push and SMS are not connected. Saving a request does not alert anyone outside the app. Contact someone directly for urgent help.';

  @override
  String get sosCapabilityUnknown =>
      'Checking available channels. Do not rely on this app for an emergency alert.';

  @override
  String get sosReceive => 'Receive help requests';

  @override
  String get sosReceiveBody =>
      'Allow Circle members to choose you as a recipient. Opening a request does not tell them you have seen it.';

  @override
  String get sosOn => 'On';

  @override
  String get sosOff => 'Off';

  @override
  String get sosReviewSetting => 'Review receiving setting';

  @override
  String get sosSettingUnknown =>
      'Your last change is unconfirmed. Review the current setting and confirm your choice.';

  @override
  String get sosSave => 'Save help request';

  @override
  String get sosSelect => 'Choose who can help';

  @override
  String get sosSelectBody =>
      'Only opted-in members of this Circle are listed. Choose up to 10 people.';

  @override
  String get sosNoContacts =>
      'No eligible recipients. Ask a Circle member to enable receiving help requests.';

  @override
  String get sosLocation => 'Include my current location';

  @override
  String get sosLocationBody =>
      'Updates run only while this screen is open. Leaving or locking the phone pauses them. Only the latest point is shared, for up to 90 seconds.';

  @override
  String get sosReviewStart => 'Review your help request';

  @override
  String get sosStartBody =>
      'These people can open your request for one hour. No sound will play. This does not contact emergency services.';

  @override
  String get sosSaved => 'Request saved';

  @override
  String get sosActive => 'Active';

  @override
  String get sosEnded => 'Resolved';

  @override
  String get sosCancelled => 'Cancelled';

  @override
  String get sosExpired => 'Expired';

  @override
  String get sosEnd => 'Resolve request';

  @override
  String get sosCancelRequest => 'Cancel request';

  @override
  String get sosEndBody =>
      'End this request and remove access to its location? Recipients may still have seen earlier information.';

  @override
  String get sosRecipients => 'People you chose';

  @override
  String get sosNoResponse => 'No response yet';

  @override
  String get sosRevoked => 'Access removed';

  @override
  String get sosSeen => 'Seen';

  @override
  String get sosContacting => 'Contacting you';

  @override
  String get sosHelping => 'Helping';

  @override
  String get sosUnavailable => 'Unable to help';

  @override
  String get sosNotification => 'Notification status';

  @override
  String get sosQueued => 'Queued; not sent';

  @override
  String get sosSending => 'Sending; unconfirmed';

  @override
  String get sosAccepted => 'Accepted by provider; device delivery unconfirmed';

  @override
  String get sosFailed => 'Failed';

  @override
  String get sosUnknown => 'Unconfirmed';

  @override
  String get sosPending => 'Save result unconfirmed';

  @override
  String get sosPendingBody =>
      'The server may have saved this request. Check its receipt, retry the same people and choices, or withdraw it. No new request will be created by a retry.';

  @override
  String get sosRetry => 'Review same request';

  @override
  String get sosWithdraw => 'Withdraw request';

  @override
  String get sosWithdrawBody =>
      'Prevent this request from starting, or cancel it if already saved? This also removes access to its location once confirmed.';

  @override
  String get sosIncoming => 'Requests for you';

  @override
  String get sosInboxEmpty =>
      'Help requests from your Circle will appear here when someone chooses you.';

  @override
  String get sosRespond => 'Send a response';

  @override
  String get sosRespondBody =>
      'This explicitly shares your selected response with the requester. It does not end their request.';

  @override
  String get sosDecline => 'Remove my access';

  @override
  String get sosDeclineBody =>
      'Remove yourself from this request? You will no longer see its location.';

  @override
  String get sosNotice => 'Change confirmed by server';

  @override
  String get sosNetwork =>
      'Could not confirm the result. Refresh to check the server before taking further action.';

  @override
  String get sosConflict =>
      'The request or setting changed. Refresh and review again.';

  @override
  String get sosStorage =>
      'Private request storage is unavailable. No new request can start until it is restored.';

  @override
  String get sosLocationPaused => 'Location updates paused';

  @override
  String get sosLocationUpdating => 'Updating location on this screen';

  @override
  String get sosResumeBody =>
      'Resume sharing your current location with the people listed on this request, while this screen is open?';

  @override
  String get sosTerminalBody =>
      'This request has ended. Its location is no longer available.';

  @override
  String get sosFreshOnly =>
      'A missing location does not indicate whether this person is safe. Contact them directly.';
}
