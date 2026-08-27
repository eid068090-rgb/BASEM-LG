package com.alsaman.app

import android.Manifest
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.drawerlayout.widget.DrawerLayout
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.*
import java.net.*
import java.util.concurrent.ConcurrentHashMap

data class Device(
    val name: String,
    val ip: String,
    val mac: String,
    val type: String
)

class MainActivity : ComponentActivity() {
    private lateinit var drawer: DrawerLayout
    private lateinit var list: RecyclerView
    private lateinit var countText: TextView
    private lateinit var progress: ProgressBar
    private lateinit var adapter: DeviceAdapter
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val discovered = ConcurrentHashMap<String, Device>()
    private var scanJob: Job? = null
    private var myIp: String? = null
    private val blue = 0xFF246BEB.toInt()
    private val bg = 0xFFF7F7F7.toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNetworkPermissions()
        buildUi()
        startScan()
    }

    private fun requestNetworkPermissions() {
        val permissions = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION
        )
        if (Build.VERSION.SDK_INT >= 33) {
            permissions += Manifest.permission.NEARBY_WIFI_DEVICES
        }
        val missing = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), 50)
        }
    }

    private fun tv(text: String, size: Float, bold: Boolean = false) =
        TextView(this).apply {
            this.text = text
            textSize = size
            setTextColor(0xFF222222.toInt())
            if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
        }

    private fun buildUi() {
        drawer = DrawerLayout(this)
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(bg)
        }

        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(18, 12, 12, 8)
            setBackgroundColor(0xFFFFFFFF.toInt())
        }

        val search = ImageButton(this).apply {
            setImageResource(R.drawable.ic_search)
            background = null
            contentDescription = "بحث"
            setOnClickListener { startScan() }
        }
        bar.addView(search, LinearLayout.LayoutParams(54, 54))

        val logo = tv("BASEM LG", 26f, true).apply { gravity = Gravity.CENTER }
        bar.addView(logo, LinearLayout.LayoutParams(0, 64, 1f))

        val menu = ImageButton(this).apply {
            setImageResource(R.drawable.ic_menu)
            background = null
            contentDescription = "القائمة"
            setOnClickListener { drawer.openDrawer(Gravity.END) }
        }
        bar.addView(menu, LinearLayout.LayoutParams(54, 54))
        content.addView(bar)

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(20, 14, 20, 4)
        }
        header.addView(tv("الأجهزة المكتشفة : ", 20f))
        countText = tv("(0)", 22f, true).apply { setTextColor(blue) }
        header.addView(countText)
        content.addView(header)

        progress = ProgressBar(this).apply { visibility = View.GONE }
        content.addView(progress, LinearLayout.LayoutParams(-1, 4))

        list = RecyclerView(this).apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            setPadding(12, 4, 12, 90)
            clipToPadding = false
        }
        adapter = DeviceAdapter()
        list.adapter = adapter
        content.addView(list, LinearLayout.LayoutParams(-1, 0, 1f))

        val network = Button(this).apply {
            text = "إعدادات الشبكة  ︶"
            textSize = 17f
            setTextColor(0xFF333333.toInt())
            setBackgroundColor(0xFFFFFFFF.toInt())
            setOnClickListener { startActivity(Intent(Settings.ACTION_WIFI_SETTINGS)) }
        }
        content.addView(network, LinearLayout.LayoutParams(-1, 62))

        drawer.addView(content, DrawerLayout.LayoutParams(-1, -1))
        val side = buildDrawer()
        val sideLp = DrawerLayout.LayoutParams(
            (resources.displayMetrics.widthPixels * .72).toInt(), -1
        )
        sideLp.gravity = Gravity.END
        drawer.addView(side, sideLp)
        setContentView(drawer)
    }

    private fun buildDrawer(): View {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xFFFFFFFF.toInt())
            setPadding(30, 42, 30, 30)
        }
        box.addView(tv("BASEM LG", 34f, true), LinearLayout.LayoutParams(-1, 70))
        box.addView(tv("الإصدار : BASEM LG - 12.0", 18f), LinearLayout.LayoutParams(-1, 55))

        fun item(text: String, action: () -> Unit) {
            val b = Button(this).apply {
                this.text = text
                textSize = 18f
                gravity = Gravity.RIGHT or Gravity.CENTER_VERTICAL
                setTextColor(0xFF222222.toInt())
                setBackgroundColor(0x00FFFFFF)
                setOnClickListener { action() }
            }
            box.addView(b, LinearLayout.LayoutParams(-1, 62))
        }

        item("إعداد جهاز جديد") { showSetup() }
        item("Breed Enter") { showBreed() }
        item("الإعدادات") { showSettings() }
        item("حول التطبيق") { showAbout() }
        item("انضم إلينا") {
            Toast.makeText(this, "صفحة التواصل قريباً", Toast.LENGTH_SHORT).show()
        }
        return box
    }

    private fun showSetup() {
        drawer.closeDrawer(Gravity.END)
        AlertDialogLike.page(
            this, "إعداد جهاز جديد",
            "خطوات مهمة لإعداد جهازك\n\n" +
            "أجهزة Ubiquiti\n\n" +
            "1- إعدادات الجهاز تعمل فقط مع الأجهزة التي تحتوي على OpenWrt أو البرامج المدعومة.\n\n" +
            "2- تأكد من إعادة تعيين الجهاز أولاً.\n\n" +
            "3- تأكد من أن الجهاز متصل بالإنترنت عبر منفذ WAN وتم إنشاء الاتصال.\n\n" +
            "4- تأكد من أن هاتفك متصل بشبكة LAN الخاصة بالجهاز.",
            "التالي"
        ) { showBreed() }
    }

    private fun showBreed() {
        AlertDialogLike.page(
            this, "Breed Enter",
            "الدخول إلى البريد ريكفري\n\n" +
            "يتم استخدام هذه الأداة للدخول إلى وضع الريكفري للأجهزة التي تحتوي على بوت لودر Breed.\n\n" +
            "استخدمها فقط مع جهاز تملكه أو لديك تصريح بإدارته.",
            "بدء البريد إنتر"
        ) {
            Toast.makeText(this, "ميزة Breed Enter قيد التطوير", Toast.LENGTH_LONG).show()
        }
    }

    private fun showSettings() {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(28, 10, 28, 10)
        }
        box.addView(tv("إعدادات الاكتشاف", 22f, true).apply { setTextColor(blue) })
        box.addView(Switch(this).apply { text = "اكتشاف أجهزة Ubuntu" })
        box.addView(Switch(this).apply { text = "اكتشاف أجهزة ROS" })
        box.addView(tv("التطبيق والمظهر العام", 22f, true).apply {
            setTextColor(blue)
            setPadding(0, 18, 0, 8)
        })
        val radio = RadioGroup(this).apply {
            orientation = RadioGroup.VERTICAL
            addView(RadioButton(this@MainActivity).apply {
                text = "النظام الافتراضي"; isChecked = true
            })
            addView(RadioButton(this@MainActivity).apply { text = "ضوء النهار" })
            addView(RadioButton(this@MainActivity).apply { text = "وضع الليل" })
        }
        box.addView(radio)
        box.addView(Switch(this).apply {
            text = "إبقاء الشاشة نشطة أثناء تشغيل التطبيق"; isChecked = true
        })
        AlertDialog.Builder(this).setTitle("الإعدادات").setView(box)
            .setPositiveButton("استعادة الإعدادات الافتراضية", null)
            .setNegativeButton("إغلاق", null).show()
    }

    private fun showAbout() {
        AlertDialog.Builder(this)
            .setTitle("حول التطبيق")
            .setMessage("BASEM LG\nالإصدار 12.0.1\nأداة مبسطة لاكتشاف وإدارة أجهزة الشبكة.")
            .setPositiveButton("حسناً", null).show()
    }

    private fun startScan() {
        scanJob?.cancel()
        discovered.clear()
        adapter.setItems(emptyList())
        countText.text = "(0)"
        progress.visibility = View.VISIBLE

        scanJob = scope.launch {
            val networkInfo = withContext(Dispatchers.IO) { getNetworkInfo() }
            if (networkInfo == null) {
                progress.visibility = View.GONE
                Toast.makeText(
                    this@MainActivity,
                    "اتصل بشبكة Wi‑Fi أولاً ثم اضغط بحث",
                    Toast.LENGTH_LONG
                ).show()
                return@launch
            }

            val (subnet, localIp) = networkInfo
            myIp = localIp

            withContext(Dispatchers.IO) {
                readArpTable().forEach { discovered[it.ip] = it }
            }
            publish()

            val jobs = (1..254).map { host ->
                launch(Dispatchers.IO) {
                    val ip = "$subnet.$host"
                    if (ip == localIp) return@launch
                    if (probe(ip)) {
                        val d = identify(ip)
                        discovered[ip] = d
                        withContext(Dispatchers.Main) { publish() }
                    }
                }
            }
            jobs.joinAll()
            progress.visibility = View.GONE
            publish()
        }
    }

    private fun getNetworkInfo(): Pair<String, String>? {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = cm.activeNetwork
        val lp = net?.let { cm.getLinkProperties(it) }

        if (lp != null) {
            val link = lp.linkAddresses.firstOrNull { it.address is Inet4Address }
            if (link != null) {
                val addr = link.address.hostAddress ?: return null
                val parts = addr.split(".").map { it.toInt() }
                if (parts.size == 4) {
                    val prefix = link.prefixLength
                    val mask = when {
                        prefix >= 24 -> intArrayOf(255, 255, 255, 0)
                        prefix >= 16 -> intArrayOf(255, 255, 0, 0)
                        else -> intArrayOf(255, 0, 0, 0)
                    }
                    val subnet =
                        "${parts[0] and mask[0]}.${parts[1] and mask[1]}." +
                        "${parts[2] and mask[2]}"
                    return Pair(subnet, addr)
                }
            }
        }

        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val ip = wm.connectionInfo.ipAddress
        if (ip == 0) return null
        val addr = "${ip and 255}.${(ip shr 8) and 255}.${(ip shr 16) and 255}.${(ip shr 24) and 255}"
        return Pair("${ip and 255}.${(ip shr 8) and 255}.${(ip shr 16) and 255}", addr)
    }

    private fun probe(ip: String): Boolean {
        val ports = intArrayOf(80, 443, 8080, 8000, 22, 23)
        for (port in ports) {
            try {
                Socket().use { s ->
                    s.connect(InetSocketAddress(ip, port), 180)
                    return true
                }
            } catch (_: Exception) {}
        }
        return try {
            InetAddress.getByName(ip).isReachable(250)
        } catch (_: Exception) {
            false
        }
    }

    private fun identify(ip: String): Device {
        var name = "جهاز شبكة"
        var type = "Network Device"
        try {
            val url = URL("http://$ip/")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 500
            conn.readTimeout = 500
            conn.requestMethod = "GET"
            val server = conn.getHeaderField("Server")?.lowercase() ?: ""
            val body = try {
                conn.inputStream.bufferedReader().readText().take(5000).lowercase()
            } catch (_: Exception) { "" }

            when {
                "openwrt" in server || "openwrt" in body || "luci" in body -> {
                    name = "OpenWrt"; type = "OpenWrt"
                }
                "dd-wrt" in server || "dd-wrt" in body -> {
                    name = "DD-WRT"; type = "DD-WRT"
                }
                "ubiquiti" in server || "ubiquiti" in body || "nanostation" in body -> {
                    name = "Ubiquiti"; type = "Ubiquiti"
                }
                "realtek" in server || "realtek" in body -> {
                    name = "Realtek Device"; type = "Realtek"
                }
            }
            conn.disconnect()
        } catch (_: Exception) {}

        return Device(name, ip, lookupMac(ip), type)
    }

    private fun readArpTable(): List<Device> {
        val out = mutableListOf<Device>()
        try {
            val lines = java.io.File("/proc/net/arp").readLines()
            for (line in lines.drop(1)) {
                val p = line.trim().split(Regex("\s+"))
                if (p.size >= 4 && p[3].matches(Regex("..:..:..:..:..:.."))) {
                    out += Device("جهاز شبكة", p[0], p[3].uppercase(), "Network Device")
                }
            }
        } catch (_: Exception) {}
        return out
    }

    private fun lookupMac(ip: String): String =
        readArpTable().firstOrNull { it.ip == ip }?.mac ?: "غير متاح"

    private suspend fun publish() {
        val items = discovered.values.sortedBy { ipToLong(it.ip) }
        adapter.setItems(items)
        countText.text = "(${items.size})"
    }

    private fun ipToLong(ip: String): Long =
        ip.split(".").fold(0L) { a, b -> (a shl 8) + b.toLong() }

    override fun onDestroy() {
        scanJob?.cancel()
        scope.cancel()
        super.onDestroy()
    }

    inner class DeviceAdapter : RecyclerView.Adapter<DeviceVH>() {
        private var items = listOf<Device>()

        fun setItems(newItems: List<Device>) {
            items = newItems
            notifyDataSetChanged()
        }

        override fun onCreateViewHolder(parent: android.view.ViewGroup, viewType: Int): DeviceVH {
            val card = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(12, 14, 18, 14)
                setBackgroundColor(0xFFFFFFFF.toInt())
                elevation = 5f
            }
            val image = ImageView(this@MainActivity).apply {
                setImageResource(R.drawable.ic_router)
                scaleType = ImageView.ScaleType.CENTER_INSIDE
            }
            card.addView(image, LinearLayout.LayoutParams(95, 88))
            val info = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.RIGHT
            }
            card.addView(info, LinearLayout.LayoutParams(0, -2, 1f))
            return DeviceVH(card, info)
        }

        override fun getItemCount() = items.size

        override fun onBindViewHolder(holder: DeviceVH, position: Int) {
            holder.bind(items[position])
        }
    }

    inner class DeviceVH(view: View, private val info: LinearLayout) : RecyclerView.ViewHolder(view) {
        fun bind(d: Device) {
            info.removeAllViews()
            info.addView(tv(d.name, 19f, true).apply { gravity = Gravity.RIGHT })
            info.addView(tv("عنوان الأي بي :  ${d.ip}", 17f).apply { gravity = Gravity.RIGHT })
            info.addView(tv("عنوان الماك :  ${d.mac}", 17f).apply { gravity = Gravity.RIGHT })
            info.addView(tv(d.type, 13f).apply {
                gravity = Gravity.RIGHT
                setTextColor(0xFF777777.toInt())
            })
            itemView.setOnClickListener {
                AlertDialog.Builder(this@MainActivity)
                    .setTitle(d.name)
                    .setMessage("IP: ${d.ip}\nMAC: ${d.mac}\nالنوع: ${d.type}")
                    .setPositiveButton("فتح صفحة الجهاز") { _, _ ->
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("http://${d.ip}")))
                        } catch (_: Exception) {}
                    }
                    .setNegativeButton("إغلاق", null)
                    .show()
            }
        }
    }
}

object AlertDialogLike {
    fun page(
        context: Context,
        title: String,
        message: String,
        button: String,
        action: () -> Unit
    ) {
        AlertDialog.Builder(context)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton(button) { _, _ -> action() }
            .setNegativeButton("رجوع", null)
            .show()
    }
}
