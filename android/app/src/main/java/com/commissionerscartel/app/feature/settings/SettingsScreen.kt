package com.commissionerscartel.app.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.viewmodel.compose.viewModel
import com.commissionerscartel.app.ui.rememberNotificationPermission

@Composable
fun SettingsScreen(modifier: Modifier = Modifier, model: SettingsViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()
    val permission = rememberNotificationPermission()
    var claiming by remember { mutableStateOf(false) }

    // Ask once, when there is finally a reason to: signing in is the moment
    // the member joins a thread eleven other people can post in.
    LaunchedEffect(state.signedIn) {
        if (state.signedIn && !permission.isGranted) permission.request()
    }

    if (claiming) {
        ClaimTeamScreen(
            claimedSwid = state.claimedSwid,
            onClaim = { model.claimTeam(it); claiming = false },
            onClose = { claiming = false },
        )
        return
    }

    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Section("Account") {
            if (state.signedIn) {
                Text(state.email ?: "Signed in", style = MaterialTheme.typography.bodyMedium)
                if (!state.isMember) {
                    Text(
                        "This address isn't on the league list, so most things stay read-only.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                OutlinedButton(onClick = { claiming = true }) {
                    Text(if (state.claimedSwid == null) "Which team is yours?" else "Change my team")
                }
                OutlinedButton(onClick = model::signOut) { Text("Sign out") }
            } else {
                SignIn(state, model)
            }
        }

        if (state.signedIn) {
            Section("Notifications") {
                if (!permission.isGranted) {
                    Text(
                        "Android needs your permission before the Cartel can " +
                            "notify you about anything.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Button(onClick = permission.request) { Text("Turn on notifications") }
                    OutlinedButton(onClick = permission.openSettings) {
                        Text("Open phone settings")
                    }
                }
                Toggle("League thread", state.preferences.messages) {
                    model.setPreferences(state.preferences.copy(messages = it))
                }
                Toggle("League news", state.preferences.news) {
                    model.setPreferences(state.preferences.copy(news = it))
                }
                Toggle("New polls", state.preferences.polls) {
                    model.setPreferences(state.preferences.copy(polls = it))
                }
                Toggle("Adds, drops and trades", state.preferences.activity) {
                    model.setPreferences(state.preferences.copy(activity = it))
                }
                Toggle("Lineup warnings", state.preferences.lineup) {
                    model.setPreferences(state.preferences.copy(lineup = it))
                }
                Toggle("My matchup", state.preferences.matchups) {
                    model.setPreferences(state.preferences.copy(matchups = it))
                }
                Toggle("Private messages", state.preferences.direct) {
                    model.setPreferences(state.preferences.copy(direct = it))
                }
                Toggle("When someone @s me", state.preferences.mentions) {
                    model.setPreferences(state.preferences.copy(mentions = it))
                }
                Text(
                    "You won't be notified about your own posts.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Section("League") {
            Row("Season", model.season.toString())
            Row("ESPN league", model.leagueId.ifBlank { "Not configured" })
        }
    }
}

@Composable
private fun SignIn(state: SettingsState, model: SettingsViewModel) {
    var email by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }

    if (state.codeSentTo == null) {
        Text(
            "Sign in to vote in polls and post in the league thread. " +
                "Only addresses on the league list can join.",
            style = MaterialTheme.typography.bodySmall,
        )
        OutlinedTextField(
            value = email,
            onValueChange = { email = it },
            label = { Text("Email") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            modifier = Modifier.fillMaxWidth(),
        )
        Button(
            onClick = { model.sendCode(email) },
            enabled = !state.busy && email.contains("@"),
        ) { Text("Email me a code") }
    } else {
        Text("Sent to ${state.codeSentTo}", style = MaterialTheme.typography.bodyMedium)
        OutlinedTextField(
            value = code,
            onValueChange = { code = it.filter(Char::isDigit).take(6) },
            label = { Text("6-digit code") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            modifier = Modifier.fillMaxWidth(),
        )
        Button(onClick = { model.verify(code) }, enabled = !state.busy && code.length == 6) {
            Text("Sign in")
        }
    }

    state.message?.let {
        Text(it, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            HorizontalDivider()
            content()
        }
    }
}

@Composable
private fun Toggle(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    androidx.compose.foundation.layout.Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun Row(label: String, value: String) {
    androidx.compose.foundation.layout.Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}
