package cachet.plugins.health

import android.content.Context
import android.os.Build
import androidx.annotation.DoNotInline
import androidx.annotation.RequiresApi

/**
 * Keeps API-34 Health Connect classes out of the fallback implementation and
 * only constructs them after the runtime API and extension gates are known.
 */
internal object PlatformHealthBodyMassDirectLookupFactory {
    fun create(
        context: Context,
        appPackageName: String,
    ): HealthBodyMassDirectLookup {
        if (Build.VERSION.SDK_INT < DIRECT_LOOKUP_MINIMUM_SDK) {
            return UnavailableBodyMassDirectLookup
        }

        return createApi34LookupIfSupported(context, appPackageName)
    }

    @DoNotInline
    @RequiresApi(34)
    private fun createApi34LookupIfSupported(
        context: Context,
        appPackageName: String,
    ): HealthBodyMassDirectLookup =
        Api34HealthBodyMassDirectLookupFactory.createIfSupported(context, appPackageName)
}
