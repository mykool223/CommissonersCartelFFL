package com.commissionerscartel.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.commissionerscartel.app.ui.CartelTheme
import com.commissionerscartel.app.ui.RootScreen
import com.commissionerscartel.app.ui.SplashGate

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            CartelTheme {
                SplashGate {
                    RootScreen()
                }
            }
        }
    }
}
