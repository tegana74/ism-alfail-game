package com.hussein.ismalfail;

import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkInfo;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.animation.AccelerateDecelerateInterpolator;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.Toast;

import androidx.activity.OnBackPressedCallback;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;

/**
 * رحلة اسم الفاعل — النشاط الرئيسي للعبة على Android
 * يدعم الهواتف والتابلت ويوفر تجربة استخدام متكاملة مع WebView
 */
public class MainActivity extends AppCompatActivity {

    public static final String GAME_URL = "https://tegana74.github.io/ism-alfail-game/";
    private static final long MIN_SPLASH_TIME_MS = 1400L;

    private WebView webView;
    private View layoutSplash;
    private View layoutError;
    private Button btnRetry;

    private boolean isPageError = false;
    private boolean splashDismissed = false;
    private long pageStartTime = 0L;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        initViews();
        setupBackNavigation();
        setupWebView();

        if (isNetworkAvailable()) {
            loadGameUrl();
        } else {
            showErrorState();
        }
    }

    private void initViews() {
        webView = findViewById(R.id.webView);
        layoutSplash = findViewById(R.id.layoutSplash);
        layoutError = findViewById(R.id.layoutError);
        btnRetry = findViewById(R.id.btnRetry);

        btnRetry.setOnClickListener(v -> {
            if (isNetworkAvailable()) {
                showLoadingState();
                loadGameUrl();
            } else {
                Toast.makeText(MainActivity.this, R.string.still_offline, Toast.LENGTH_SHORT).show();
            }
        });
    }

    private void setupBackNavigation() {
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                if (layoutError.getVisibility() == View.VISIBLE) {
                    finish();
                    return;
                }
                if (webView != null && webView.canGoBack()) {
                    webView.goBack();
                } else {
                    showExitDialog();
                }
            }
        });
    }

    private void showExitDialog() {
        new AlertDialog.Builder(this)
                .setTitle(R.string.exit_dialog_title)
                .setMessage(R.string.exit_dialog_message)
                .setPositiveButton(R.string.exit_dialog_yes, (dialog, which) -> finish())
                .setNegativeButton(R.string.exit_dialog_cancel, (dialog, which) -> dialog.dismiss())
                .setCancelable(true)
                .show();
    }

    private void setupWebView() {
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);

        // Security settings
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);

        // Responsive & Screen display settings for Phone & Tablet
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        settings.setSupportZoom(false);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setTextZoom(100);

        // Cookie & Session persistence for Supabase Auth
        CookieManager cookieManager = CookieManager.getInstance();
        cookieManager.setAcceptCookie(true);
        cookieManager.setAcceptThirdPartyCookies(webView, true);

        webView.setWebChromeClient(new WebChromeClient());
        webView.setWebViewClient(new GameWebViewClient());
    }

    private void loadGameUrl() {
        isPageError = false;
        pageStartTime = System.currentTimeMillis();
        webView.loadUrl(GAME_URL);
    }

    private void showLoadingState() {
        isPageError = false;
        layoutError.setVisibility(View.GONE);
        layoutSplash.setVisibility(View.VISIBLE);
        layoutSplash.setAlpha(1.0f);
        splashDismissed = false;
    }

    private void showErrorState() {
        isPageError = true;
        dismissSplashImmediately();
        webView.setVisibility(View.GONE);
        layoutError.setVisibility(View.VISIBLE);
    }

    private void showGameContent() {
        if (isPageError) return;

        layoutError.setVisibility(View.GONE);
        webView.setVisibility(View.VISIBLE);

        long elapsed = System.currentTimeMillis() - pageStartTime;
        long remaining = Math.max(0L, MIN_SPLASH_TIME_MS - elapsed);

        mainHandler.postDelayed(this::dismissSplashWithAnimation, remaining);
    }

    private void dismissSplashWithAnimation() {
        if (splashDismissed || layoutSplash == null) return;
        splashDismissed = true;

        layoutSplash.animate()
                .alpha(0.0f)
                .setDuration(350L)
                .setInterpolator(new AccelerateDecelerateInterpolator())
                .withEndAction(() -> layoutSplash.setVisibility(View.GONE))
                .start();
    }

    private void dismissSplashImmediately() {
        splashDismissed = true;
        if (layoutSplash != null) {
            layoutSplash.setVisibility(View.GONE);
        }
    }

    private boolean isNetworkAvailable() {
        ConnectivityManager cm = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
        if (cm == null) return false;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Network network = cm.getActiveNetwork();
            if (network == null) return false;
            NetworkCapabilities caps = cm.getNetworkCapabilities(network);
            return caps != null && (
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
            );
        } else {
            NetworkInfo info = cm.getActiveNetworkInfo();
            return info != null && info.isConnected();
        }
    }

    private boolean handleExternalLink(Uri uri) {
        if (uri == null) return false;
        String scheme = uri.getScheme();
        String host = uri.getHost();

        // Handle phone, email, messaging schemes
        if ("tel".equalsIgnoreCase(scheme) || "mailto".equalsIgnoreCase(scheme) ||
            "sms".equalsIgnoreCase(scheme) || "whatsapp".equalsIgnoreCase(scheme)) {
            try {
                Intent intent = new Intent(Intent.ACTION_VIEW, uri);
                startActivity(intent);
                return true;
            } catch (Exception e) {
                return true;
            }
        }

        // Allow game domain and Supabase APIs to stay in WebView
        if (host != null && (host.contains("github.io") || host.contains("supabase.co"))) {
            return false;
        }

        // Other external links open in system browser
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW, uri);
            startActivity(intent);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private class GameWebViewClient extends WebViewClient {

        @Override
        public void onPageStarted(WebView view, String url, Bitmap favicon) {
            super.onPageStarted(view, url, favicon);
            isPageError = false;
        }

        @Override
        public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
            super.onReceivedError(view, request, error);
            if (request.isForMainFrame()) {
                showErrorState();
            }
        }

        @SuppressWarnings("deprecation")
        @Override
        public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
            super.onReceivedError(view, errorCode, description, failingUrl);
            showErrorState();
        }

        @Override
        public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse errorResponse) {
            super.onReceivedHttpError(view, request, errorResponse);
            if (request.isForMainFrame() && errorResponse != null && errorResponse.getStatusCode() >= 500) {
                showErrorState();
            }
        }

        @Override
        public void onPageFinished(WebView view, String url) {
            super.onPageFinished(view, url);
            if (!isPageError) {
                showGameContent();
            }
        }

        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            if (request != null && request.getUrl() != null) {
                return handleExternalLink(request.getUrl());
            }
            return false;
        }

        @SuppressWarnings("deprecation")
        @Override
        public boolean shouldOverrideUrlLoading(WebView view, String url) {
            if (url != null) {
                return handleExternalLink(Uri.parse(url));
            }
            return false;
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (webView != null) webView.onResume();
    }

    @Override
    protected void onPause() {
        if (webView != null) webView.onPause();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }
}
