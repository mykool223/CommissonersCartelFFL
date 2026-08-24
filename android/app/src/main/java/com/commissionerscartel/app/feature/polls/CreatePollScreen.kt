package com.commissionerscartel.app.feature.polls

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Any member can start a poll; the RPC enforces that in Postgres. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreatePollScreen(onCancel: () -> Unit, onCreate: (String, List<String>) -> Unit) {
    var question by remember { mutableStateOf("") }
    val options = remember { mutableStateListOf("", "") }

    val filled = options.map { it.trim() }.filter { it.isNotEmpty() }
    val canSubmit = question.isNotBlank() && filled.size >= 2

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New poll") },
                navigationIcon = {
                    IconButton(onClick = onCancel) {
                        Icon(Icons.Filled.Close, contentDescription = "Cancel")
                    }
                },
                actions = {
                    TextButton(onClick = { onCreate(question.trim(), filled) }, enabled = canSubmit) {
                        Text("Post")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = question,
                onValueChange = { question = it },
                label = { Text("Question") },
                modifier = Modifier.fillMaxWidth(),
            )

            options.forEachIndexed { index, value ->
                OutlinedTextField(
                    value = value,
                    onValueChange = { options[index] = it },
                    label = { Text("Option ${index + 1}") },
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // Ten is the server's limit, so stop offering more than it accepts.
            if (options.size < 10) {
                Button(onClick = { options.add("") }) { Text("Add option") }
            }

            Text(
                "Two options minimum. Everyone in the league can vote once, and " +
                    "results stay hidden until they do.",
                style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
            )
        }
    }
}
