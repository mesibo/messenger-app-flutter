/*
 * mesibo Messenger in Flutter: the same app as the native mesibo messengers, built with the mesibo
 * Flutter SDK (https://pub.dev/packages/mesibo).
 *
 *   - welcome and login screens (MesiboUIHelper): phone number and verification code, verified by
 *     the messenger backend (backend.dart), which returns the user's mesibo access token
 *   - a new user sets their name and picture (MesiboUI.launchEditProfile)
 *   - the chat list is the main screen (MesiboUI.launchUserList), with calls, "Customize" and
 *     "Sign out"
 *   - Customize (MesiboUI.launchCustomize): the look chosen for the light and for the dark theme,
 *     saved by mesibo and applied whenever that theme is on
 *
 * The screens are mesibo's native screens, shown over the Flutter screen below.
 */

import 'package:flutter/material.dart';
import 'package:mesibo/mesibo.dart';

import 'backend.dart';

// the brand color of the native mesibo messengers
const int BRAND_COLOR = 0xff00868b;

// the ids of the "Customize" and "Sign out" items in the chat list's menu
const String MENU_CUSTOMIZE = "customize";
const String MENU_SIGNOUT = "signout";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MessengerApp());
}

class MessengerApp extends StatelessWidget {
  const MessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mesibo Messenger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(BRAND_COLOR)),
      home: const Messenger(),
    );
  }
}

/**
 * The Flutter screen under mesibo's screens. It starts the app: the chat list when the user is
 * signed in, else the welcome screen.
 */
class Messenger extends StatefulWidget {
  const Messenger({super.key});

  @override
  State<Messenger> createState() => _MessengerState();
}

class _MessengerState extends State<Messenger> with WidgetsBindingObserver
    implements MesiboConnectionListener, MesiboUIHelperListener, MesiboEditProfileListener, MesiboUIMenuListener {

  final Mesibo _mesibo = Mesibo();
  final MesiboUI _ui = MesiboUI();
  final Backend _backend = Backend();

  // a new user: after signing in, the profile first, then the chat list
  bool _newUser = false;

  // signing out: once, also when the token is rejected more than once
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();

    // the app's foreground state, for read receipts and presence
    WidgetsBinding.instance.addObserver(this);

    // after the first frame: mesibo's screens are shown over this one
    WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp) => _start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _mesibo.setAppInForeground(AppLifecycleState.resumed == state);
  }

  @override
  Widget build(BuildContext context) {
    // seen only for a moment, while mesibo's screens open
    return const Scaffold(
      body: Center(
        child: Text("mesibo", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
      ),
    );
  }


  // -----------------------------------------------------------------------
  // start
  // -----------------------------------------------------------------------

  /** signed in before: the chat list; else the welcome screen */
  Future<void> _start() async {
    // the menu must be set before the chat list opens
    await _setupUi();

    String? token = await _backend.savedToken();
    if (null == token) {
      MesiboUIHelper().launchWelcome(_welcomeOptions(), _loginOptions(), this);
      return;
    }

    await _startMesibo(token);
    _showChats();
  }

  /** mesibo for the signed in user */
  Future<void> _startMesibo(String token) async {
    _mesibo.setListener(this);
    await _mesibo.setAccessToken(token);
    await _mesibo.setDatabase("messenger.db");

    // end-to-end encryption: the user turns it on or off in mesibo's Encryption screen; mesibo
    // keeps the choice and applies it at start
    await _mesibo.start();

    // finds which phone contacts use the app
    _mesibo.getPhoneContactsManager().start();
  }

  /**
   * The texts and the menu of mesibo's screens: set once. mesibo keeps the settings and applies
   * them again whenever a theme is applied (with the look saved in Customize for it).
   */
  Future<void> _setupUi() async {
    MesiboUiConfig config = await _ui.getConfig();
    config.userList.emptyMessage = "No messages! Click on the message icon below to start messaging!";
    config.profileViewer.showAddress = true;
    await _ui.setConfig(config);

    // calls in chats (the default menu); "End-to-end encryption" (turn it on or off),
    // "Customize" and "Sign out" in the chat list's menu
    List<MesiboUIMenuItem> menu = MesiboUI.defaultMenu();

    // voice and video calls on profiles (the round buttons under the name) and in the chat
    // list's profile popup; during a call, they bring it back
    for (int screen in [MesiboUI.SCREEN_PROFILE, MesiboUI.SCREEN_PROFILE_POPUP]) {
      menu.add(MesiboUIMenuItem(id: MesiboUI.MENU_VOICECALL, title: "Voice", screen: screen));
      menu.add(MesiboUIMenuItem(id: MesiboUI.MENU_VIDEOCALL, title: "Video", screen: screen));
    }

    menu.add(MesiboUIMenuItem(id: MesiboUI.MENU_ENCRYPTION, title: "End-to-end encryption", icon: MesiboUI.ICON_LOCK,
        screen: MesiboUI.SCREEN_USERLIST, button: false));
    menu.add(MesiboUIMenuItem(id: MENU_CUSTOMIZE, title: "Customize", icon: MesiboUI.ICON_SETTINGS,
        screen: MesiboUI.SCREEN_USERLIST, button: false));
    menu.add(MesiboUIMenuItem(id: MENU_SIGNOUT, title: "Sign out", icon: MesiboUI.ICON_LOGOUT,
        screen: MesiboUI.SCREEN_USERLIST, button: false));
    _ui.setMenu(menu, this);
  }


  // -----------------------------------------------------------------------
  // the look from Customize
  // -----------------------------------------------------------------------

  /** Customize: the look of the theme on now, saved by mesibo and used at once */
  void _customize() {
    _ui.launchCustomize();
  }

  /** the main screen: on Android, back sends the app to the background */
  void _showChats() {
    _ui.launchUserList(keepRunning: true);
  }


  // -----------------------------------------------------------------------
  // welcome and login
  // -----------------------------------------------------------------------

  MesiboWelcomeOptions _welcomeOptions() {
    return MesiboWelcomeOptions(
      // the image of the app with this name: res/drawable on Android, Assets.xcassets on iOS
      logo: "mesibo_logo_white",
      title: "Messaging & Calls in your apps",
      description: "Add messaging, video and voice calls & conferencing in your apps in no time.",
      githubUrl: "https://github.com/mesibo",
      buttonText: "Get Started",
    );
  }

  MesiboLoginOptions _loginOptions() {
    return MesiboLoginOptions(
      // the backend does not send verification codes: testers generate them in the console
      note: "This demo app will NOT send verification code. You can generate yourself from the mesibo console https://console.mesibo.com",
      noteColor: 0xffb45309,
      noteBorderColor: 0x55ffb900,
      noteBackgroundColor: 0x14ffb900,
      codeMessage: "Enter the verification code for %PHONE% generated from the mesibo console",
      accentColor: BRAND_COLOR,
      buttonColor: BRAND_COLOR,
      buttonTextColor: 0xffffffff,
    );
  }

  /** the login screen: code null: send a code; else sign in and start mesibo */
  @override
  Future<bool> MesiboUIHelper_onLogin(String para_phone, String? para_code) async {
    LoginResult result = await _backend.login(para_phone, para_code);
    if (!result.ok || null == para_code)
      return result.ok;

    _newUser = result.newUser;
    await _startMesibo(result.token!);
    return true;
  }

  /** signed in, and the login screens have closed: a new user's profile, else the chat list */
  @override
  void MesiboUIHelper_onLoginComplete() {
    if (_newUser) {
      _ui.launchEditProfile(true, this);
      return;
    }

    _showChats();
  }

  /** the new user saved their profile, and the screen has closed */
  @override
  void MesiboEditProfile_onSaved(MesiboProfile profile, bool para_newUser) {
    if (para_newUser)
      _showChats();
  }


  // -----------------------------------------------------------------------
  // menu and sign out
  // -----------------------------------------------------------------------

  @override
  Future<bool> MesiboUI_onMenuItem(MesiboProfile? profile, String para_id) async {
    if (MENU_SIGNOUT == para_id) {
      _signOut();
      return true;
    }

    if (MENU_CUSTOMIZE == para_id) {
      _customize();
      return true;
    }

    // the built-in items (calls) do their own action
    return false;
  }

  /** signs out, closes mesibo's screens and shows the login screen */
  Future<void> _signOut() async {
    if (_signingOut)
      return;

    _signingOut = true;

    await _backend.logout();
    await _mesibo.stop();
    await _mesibo.reset();
    await _ui.closeAllScreens();

    _signingOut = false;
    MesiboUIHelper().launchLogin(_loginOptions(), this);
  }

  /** a token the server rejects (e.g. signed out on another device): sign in again */
  @override
  void Mesibo_onConnectionStatus(int status) {
    if (Mesibo.MESIBO_STATUS_AUTHFAIL == status)
      _signOut();
  }
}
