package org.vanaclient;

import android.app.NativeActivity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.DocumentsContract;
import android.provider.Settings;
import android.util.Log;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;

/**
 * NativeActivity for {@code libvana_client.so}: full screen, and the system screens Rust asks for (All files access,
 * the browser, the folder picker).
 */
public class VanaClientNativeActivity extends NativeActivity {
    private static final String TAG = "VanaClient";
    private static final int REQUEST_FOLDER = 9001;

    static {
        System.loadLibrary("c++_shared");
        System.loadLibrary("vana_client");
    }

    private static native void onFolderPicked(String path);
    private static native void onFolderCancelled();
    private static native void nativeAfterUiActivity();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        applyImmersiveUi();
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
        nativeAfterUiActivity();
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

    /** {@code startPath}: an absolute path on primary storage to open near, else Download. */
    public void requestFolderPicker(String startPath) {
        runOnUiThread(() -> {
            try {
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
                Uri initial = initialFolderUri(startPath);
                if (initial != null) {
                    intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, initial);
                }
                startActivityForResult(intent, REQUEST_FOLDER);
            } catch (RuntimeException e) {
                Log.e(TAG, "folder picker", e);
                onFolderCancelled();
            }
        });
    }

    private static Uri initialFolderUri(String startPath) {
        String rel = primaryRelative(startPath);
        if (rel == null || rel.isEmpty()) {
            rel = "Download";
        } else {
            // The parent, so the folder itself or one above it can be picked.
            int slash = rel.lastIndexOf('/');
            if (slash > 0) {
                rel = rel.substring(0, slash);
            }
        }
        try {
            return DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:" + rel);
        } catch (RuntimeException e) {
            return null;
        }
    }

    private static String primaryRelative(String absPath) {
        String primary = Environment.getExternalStorageDirectory().getAbsolutePath();
        if (absPath == null || !absPath.startsWith(primary)) {
            return null;
        }
        String rel = absPath.substring(primary.length());
        return rel.startsWith("/") ? rel.substring(1) : rel;
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQUEST_FOLDER) {
            super.onActivityResult(requestCode, resultCode, data);
            return;
        }
        String path = resultCode == RESULT_OK && data != null && data.getData() != null ? treePath(data.getData()) : null;
        if (path == null) {
            onFolderCancelled();
        } else {
            onFolderPicked(path);
        }
    }

    /** The plain path of a tree on primary storage (read directly under All files access). */
    private static String treePath(Uri treeUri) {
        String docId = DocumentsContract.getTreeDocumentId(treeUri);
        if (docId == null || !docId.startsWith("primary:")) {
            Log.w(TAG, "folder not on primary storage: " + docId);
            return null;
        }
        return Environment.getExternalStorageDirectory().getAbsolutePath() + "/" + Uri.decode(docId.substring(8));
    }
}
