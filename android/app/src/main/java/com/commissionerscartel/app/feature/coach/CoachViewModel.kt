package com.commissionerscartel.app.feature.coach

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.commissionerscartel.app.data.Config
import com.commissionerscartel.app.data.Session
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

data class CoachTurn(val text: String, val fromCoach: Boolean)

data class CoachState(
    val turns: List<CoachTurn> = emptyList(),
    val busy: Boolean = false,
)

class CoachViewModel : ViewModel() {
    private val http = HttpClient(OkHttp)
    private val json = Json { ignoreUnknownKeys = true }

    private val _state = MutableStateFlow(CoachState())
    val state: StateFlow<CoachState> = _state.asStateFlow()

    fun ask(question: String) {
        if (question.isBlank() || _state.value.busy) return

        _state.value = _state.value.copy(
            turns = _state.value.turns + CoachTurn(question, fromCoach = false),
            busy = true,
        )

        viewModelScope.launch {
            val reply = runCatching { request(question) }
                .getOrElse { "Coach Madden isn't answering just now." }
            _state.value = _state.value.copy(
                turns = _state.value.turns + CoachTurn(reply, fromCoach = true),
                busy = false,
            )
        }
    }

    private suspend fun request(question: String): String {
        // The member's own token, not the anon key: the function answers about
        // whoever is asking, so it has to know who that is.
        val token = Session.accessToken() ?: return "Sign in first, under Settings."

        val response = http.post("${Config.supabaseUrl}/functions/v1/coach") {
            header("Authorization", "Bearer $token")
            header("apikey", Config.supabaseAnonKey)
            header("Content-Type", "application/json")
            setBody(buildJsonObject { put("question", question) }.toString())
        }
        val body = json.decodeFromString<JsonObject>(response.bodyAsText())
        // The function returns a readable reason for every refusal, so show it
        // rather than a generic failure.
        return body["answer"]?.jsonPrimitive?.content
            ?: body["error"]?.jsonPrimitive?.content
            ?: "No answer came back."
    }
}
