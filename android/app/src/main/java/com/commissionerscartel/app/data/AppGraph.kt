package com.commissionerscartel.app.data

/**
 * The app's dependencies, in one place. Deliberately a plain object rather than
 * a DI framework: there are three of them and they all live for the process.
 */
object AppGraph {
    val espn: EspnClient by lazy { EspnClient() }
    val season: Int get() = Config.currentSeason()
}
