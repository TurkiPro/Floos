package com.turkisecurity.floos

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth: the
// Android BiometricPrompt behind the app lock is a fragment and needs a
// FragmentActivity host, otherwise authenticate() throws at runtime.
class MainActivity : FlutterFragmentActivity()
