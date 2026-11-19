/*
 * The messenger backend: sign in with a phone number and a verification code, and sign out.
 * The same requests as the native mesibo messenger apps (SampleAPI on iOS).
 *
 * Signing in returns the user's mesibo access token, created by the backend for this app's App ID.
 * The token is saved on the device, so the user stays signed in.
 */

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// the messenger backend
const String API_URL = "https://messenger.mesibo.com";

// the App ID of this app (the Android applicationId and the iOS bundle identifier): the backend
// creates the access token for it, and a token works only in an app with this App ID
const String APP_ID = "com.mesibo.flutter.messenger";

// keys of the saved values
const String TOKEN_KEY = "token";
const String DEVICE_KEY = "device";

/** the result of a sign in request */
class LoginResult {
  final bool ok;
  final String? token;
  final bool newUser;      // no profile yet: the user sets a name first

  LoginResult(this.ok, {this.token, this.newUser = false});
}

class Backend {

  /** the saved access token, null when not signed in */
  Future<String?> savedToken() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    String? token = preferences.getString(TOKEN_KEY);
    return (null == token || token.isEmpty) ? null : token;
  }

  /**
   * code null: asks the backend to send a verification code to phone (the number with the country
   * code). With code: signs in; the access token is saved.
   */
  Future<LoginResult> login(String phone, String? code) async {
    Map<String, Object?> request = <String, Object?>{
      "op": "login",
      "appid": APP_ID,
      "phone": phone,
    };

    if (null != code) {
      request["otp"] = code;
      request["device"] = await _deviceId();
    }

    Map<String, Object?>? response = await _call(request);
    if (null == response)
      return LoginResult(false);

    // a code was sent
    if (null == code)
      return LoginResult(true);

    String? token = response["token"] as String?;
    if (null == token || token.isEmpty)
      return LoginResult(false);

    SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(TOKEN_KEY, token);

    return LoginResult(true, token: token, newUser: _isNewUser(response["new_user"]));
  }

  /** signs out: tells the backend (ignoring the result) and forgets the token */
  Future<void> logout() async {
    String? token = await savedToken();

    SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.remove(TOKEN_KEY);

    if (null != token)
      await _call(<String, Object?>{"op": "logout", "token": token});
  }


  // -----------------------------------------------------------------------
  // requests
  // -----------------------------------------------------------------------

  /** posts the request; the response when its result is OK, else null */
  Future<Map<String, Object?>?> _call(Map<String, Object?> request) async {
    // the device type: 1 Android, 2 iOS (as mesibo's getDeviceType)
    request["dt"] = Platform.isIOS ? "2" : "1";

    try {
      http.Response reply = await http.post(Uri.parse(API_URL),
          headers: <String, String>{"Content-Type": "application/json"},
          body: jsonEncode(request));

      Object? json = jsonDecode(reply.body);
      if (json is! Map<String, Object?>)
        return null;

      if ("OK" != json["result"]) {
        print("messenger backend: ${json["op"]} failed: ${json["error"]} ${json["errmsg"] ?? ""}");
        return null;
      }

      return json;
    } catch (e) {
      print("messenger backend: ${request["op"]} failed: $e");
      return null;
    }
  }

  /** new_user in the sign in response: true, 1 or "1" / "true" */
  bool _isNewUser(Object? value) {
    if (value is bool)
      return value;

    if (value is num)
      return 0 != value;

    if (value is String)
      return "1" == value || "true" == value.toLowerCase();

    return false;
  }

  /** an id of this installation, sent when signing in (as the native apps send the device id) */
  Future<String> _deviceId() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    String? id = preferences.getString(DEVICE_KEY);
    if (null != id)
      return id;

    Random random = Random.secure();
    id = List<String>.generate(16, (int index) => random.nextInt(256).toRadixString(16).padLeft(2, "0")).join();
    await preferences.setString(DEVICE_KEY, id);
    return id;
  }
}
