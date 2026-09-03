package group.innoxsz.forum;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends Activity {
    private static final String PUBLIC_BASE_URL = "https://kezaiforum.xyz";
    private static final String LAN_BASE_URL = "http://10.10.24.116";
    private static final int FILE_CHOOSER_REQUEST = 10;
    private static final String PREFS_NAME = "kezai_community_account";
    private static final String PREF_ACCOUNT_REMEMBERED = "account_remembered";
    private static final String PREF_LAST_BASE_URL = "last_base_url";
    private WebView webView;
    private ValueCallback<Uri[]> fileCallback;
    private SharedPreferences preferences;
    private TextView connectionLabel;
    private String activeBaseUrl = PUBLIC_BASE_URL;
    private boolean triedLanFallback;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        preferences = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        String rememberedBase = preferences.getString(PREF_LAST_BASE_URL, PUBLIC_BASE_URL);
        if (LAN_BASE_URL.equals(rememberedBase) && hasAuthenticationCookie(LAN_BASE_URL)) {
            activeBaseUrl = LAN_BASE_URL;
        }
        buildInterface();
        configureWebView();
        if (savedInstanceState == null || webView.restoreState(savedInstanceState) == null) {
            webView.loadUrl(activeBaseUrl + (hasAuthenticationCookie(activeBaseUrl) ? "/latest" : "/join"));
        }
    }

    private void buildInterface() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.rgb(7, 29, 73));

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(12), 0, dp(12), 0);
        header.setBackgroundColor(Color.rgb(7, 29, 73));

        ImageView mark = new ImageView(this);
        mark.setImageResource(R.drawable.kezai_launcher_v2);
        mark.setScaleType(ImageView.ScaleType.CENTER_CROP);
        header.addView(mark, new LinearLayout.LayoutParams(dp(38), dp(38)));

        TextView title = new TextView(this);
        title.setText("科仔交流社区");
        title.setTextColor(Color.WHITE);
        title.setTextSize(17);
        title.setGravity(Gravity.CENTER_VERTICAL);
        title.setPadding(dp(10), 0, 0, 0);
        header.addView(title, new LinearLayout.LayoutParams(0, dp(56), 1));

        connectionLabel = new TextView(this);
        connectionLabel.setText(activeBaseUrl.equals(LAN_BASE_URL) ? "内网" : "公网");
        connectionLabel.setTextColor(Color.rgb(7, 29, 73));
        connectionLabel.setTextSize(12);
        connectionLabel.setGravity(Gravity.CENTER);
        connectionLabel.setPadding(dp(10), dp(5), dp(10), dp(5));
        connectionLabel.setBackgroundColor(Color.rgb(231, 240, 255));
        header.addView(connectionLabel, new LinearLayout.LayoutParams(dp(54), dp(30)));
        root.addView(header, new LinearLayout.LayoutParams(-1, dp(56)));

        webView = new WebView(this);
        root.addView(webView, new LinearLayout.LayoutParams(-1, 0, 1));

        LinearLayout nav = new LinearLayout(this);
        nav.setOrientation(LinearLayout.HORIZONTAL);
        nav.setPadding(dp(8), dp(4), dp(8), dp(4));
        nav.setBackgroundColor(Color.rgb(247, 248, 250));
        nav.addView(navButton("论坛首页", "/latest"), new LinearLayout.LayoutParams(0, dp(48), 1));
        nav.addView(navButton("公屏聊天", "/chat"), new LinearLayout.LayoutParams(0, dp(48), 1));
        nav.addView(navButton("我的编号", "/join/account"), new LinearLayout.LayoutParams(0, dp(48), 1));
        setContentView(root);
    }

    private Button navButton(String label, String path) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextSize(15);
        button.setTextColor(Color.rgb(23, 105, 224));
        button.setAllCaps(false);
        button.setBackgroundColor(Color.TRANSPARENT);
        button.setOnClickListener(v -> webView.loadUrl(activeBaseUrl + path));
        return button;
    }

    private void configureWebView() {
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setUserAgentString(settings.getUserAgentString() + " KezaiCommunityAndroid/1.3");

        CookieManager cookieManager = CookieManager.getInstance();
        cookieManager.setAcceptCookie(true);
        cookieManager.setAcceptThirdPartyCookies(webView, true);

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (isCommunityHost(uri.getHost())) return false;
                startActivity(new Intent(Intent.ACTION_VIEW, uri));
                return true;
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (!request.isForMainFrame()) return;
                Uri failedUri = request.getUrl();
                if ("kezaiforum.xyz".equalsIgnoreCase(failedUri.getHost()) && !triedLanFallback) {
                    triedLanFallback = true;
                    activeBaseUrl = LAN_BASE_URL;
                    updateConnectionLabel();
                    String target = preferences.getBoolean(PREF_ACCOUNT_REMEMBERED, false) ? "/latest" : "/join";
                    webView.loadUrl(activeBaseUrl + target);
                    return;
                }
                showOffline();
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                CookieManager.getInstance().flush();
                Uri uri = Uri.parse(url);
                if ("kezaiforum.xyz".equalsIgnoreCase(uri.getHost())) activeBaseUrl = PUBLIC_BASE_URL;
                if ("10.10.24.116".equals(uri.getHost())) activeBaseUrl = LAN_BASE_URL;
                updateConnectionLabel();
                if (hasAuthenticationCookie(activeBaseUrl)) {
                    preferences.edit()
                        .putBoolean(PREF_ACCOUNT_REMEMBERED, true)
                        .putString(PREF_LAST_BASE_URL, activeBaseUrl)
                        .apply();
                }
            }
        });

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (fileCallback != null) fileCallback.onReceiveValue(null);
                fileCallback = callback;
                Intent intent = params.createIntent();
                intent.setType("image/*");
                try {
                    startActivityForResult(intent, FILE_CHOOSER_REQUEST);
                } catch (ActivityNotFoundException e) {
                    fileCallback = null;
                    Toast.makeText(MainActivity.this, "未找到图片选择器", Toast.LENGTH_SHORT).show();
                }
                return true;
            }
        });
    }

    private void showOffline() {
        String target = preferences.getBoolean(PREF_ACCOUNT_REMEMBERED, false) ? "/latest" : "/join";
        String html = "<html><meta name='viewport' content='width=device-width'><body style='margin:0;background:#071d49;font-family:sans-serif;text-align:center;padding:52px 24px;color:#fff'><img src='file:///android_res/drawable/kezai_launcher_v2.png' style='width:104px;height:104px;border-radius:28px;object-fit:cover'><h2>暂时无法连接社区</h2><p style='color:#d7dfec;line-height:1.7'>你可以先尝试公网入口；连接办公室网络后，也可以切换到内网入口。</p><p><a style='display:inline-block;text-decoration:none;font-size:16px;padding:12px 20px;border-radius:10px;background:#1769e0;color:white;margin:5px' href='" + PUBLIC_BASE_URL + target + "'>公网重试</a><a style='display:inline-block;text-decoration:none;font-size:16px;padding:12px 20px;border-radius:10px;background:#ff5d55;color:white;margin:5px' href='" + LAN_BASE_URL + target + "'>内网连接</a></p></body></html>";
        webView.loadDataWithBaseURL(activeBaseUrl, html, "text/html", "UTF-8", null);
    }

    private boolean hasAuthenticationCookie(String baseUrl) {
        String cookies = CookieManager.getInstance().getCookie(baseUrl);
        return cookies != null && cookies.contains("_t=");
    }

    private boolean isCommunityHost(String host) {
        return "kezaiforum.xyz".equalsIgnoreCase(host) || "10.10.24.116".equals(host);
    }

    private void updateConnectionLabel() {
        if (connectionLabel != null) {
            connectionLabel.setText(activeBaseUrl.equals(LAN_BASE_URL) ? "内网" : "公网");
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == FILE_CHOOSER_REQUEST && fileCallback != null) {
            Uri[] result = resultCode == RESULT_OK && data != null && data.getData() != null ? new Uri[]{data.getData()} : null;
            fileCallback.onReceiveValue(result);
            fileCallback = null;
        }
    }

    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) webView.goBack(); else super.onBackPressed();
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        webView.saveState(outState);
        super.onSaveInstanceState(outState);
    }

    @Override
    protected void onStop() {
        CookieManager.getInstance().flush();
        super.onStop();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
