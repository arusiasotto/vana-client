package org.vanaclient;

import android.app.NativeActivity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.Settings;
import java.io.File;
import androidx.core.content.FileProvider;
import android.util.Log;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;

/**
 * NativeActivity for {@code libvana_client.so}: full screen, and the system screens Rust asks for (All files access
 * and the browser). Game folders are chosen in the in-app browser under shared storage.
 */
public class VanaClientNativeActivity extends NativeActivity {
    private static final String TAG = "VanaClient";

    static {
        System.loadLibrary("c++_shared");
        System.loadLibrary("vana_client");
    }

    private static native void nativeAfterUiActivity();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        applyImmersiveUi();
        suppressSystemKeyboard();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            applyImmersiveUi();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        applyImmersiveUi();
        suppressSystemKeyboard();
        nativeAfterUiActivity();
    }

    /** Keep the Android IME hidden; in-game and lobby text use retail swkbd (Back), not the system keyboard. */
    private void suppressSystemKeyboard() {
        final Window window = getWindow();
        if (window == null) {
            return;
        }
        window.setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN
                        | WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING);
        final View decor = window.getDecorView();
        if (decor != null) {
            decor.setShowSoftInputOnFocus(false);
            final InputMethodManager imm = (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
            if (imm != null) {
                imm.hideSoftInputFromWindow(decor.getWindowToken(), 0);
            }
        }
    }

    /** Status and navigation bars hidden; a swipe from the edge shows them for a moment. */
    private void applyImmersiveUi() {
        final Window window = getWindow();
        if (window == null) {
            return;
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false);
            final WindowInsetsController c = window.getInsetsController();
            if (c != null) {
                c.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            window.getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                            | View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN);
        }
    }

    public boolean hasAllFilesAccess() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager();
    }

    /** Opens Settings at this app's All files access switch (else the list of apps). */
    public void requestAllFilesAccess() {
        runOnUiThread(() -> {
            try {
                Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
                intent.setData(Uri.parse("package:" + getPackageName()));
                startActivity(intent);
            } catch (RuntimeException e) {
                try {
                    startActivity(new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION));
                } catch (RuntimeException e2) {
                    Log.e(TAG, "All files access settings", e2);
                }
            }
        });
    }

    public void openBrowser(String url) {
        runOnUiThread(() -> {
            try {
                startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
            } catch (RuntimeException e) {
                Log.e(TAG, "openBrowser", e);
            }
        });
    }

    /** Installed APK version (matches android-v* release tags after the android- prefix). */
    public String appVersionName() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (PackageManager.NameNotFoundException e) {
            return "0";
        }
    }

    /** Where the client downloads an update APK (cache; readable by FileProvider). */
    public String updateApkPath() {
        return new File(getCacheDir(), "vana-client-update.apk").getAbsolutePath();
    }

    /** Opens the system installer for an APK the client downloaded. */
    public void installApk(String path) {
        runOnUiThread(() -> {
            try {
                File file = new File(path);
                if (!file.isFile()) {
                    Log.e(TAG, "installApk: missing " + path);
                    return;
                }
                Uri uri = FileProvider.getUriForFile(this, getPackageName() + ".fileprovider", file);
                Intent intent = new Intent(Intent.ACTION_VIEW);
                intent.setDataAndType(uri, "application/vnd.android.package-archive");
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(intent);
            } catch (RuntimeException e) {
                Log.e(TAG, "installApk", e);
            }
        });
    }
}