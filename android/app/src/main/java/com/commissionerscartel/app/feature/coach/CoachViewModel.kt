package com.commissionerscartel.app.feature.coach

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.commissionerscartel.app.data.Config
import com.commissionerscartel.app.data.Session
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.header
import io.ktor.client.request.get
import io.ktor.client.request.parameter
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
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
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

    private var loadedHistory = false

    /**
     * Brings back what was said before.
     *
     * The conversation lives on the server rather than in this view model, so
     * it survives the app being closed and is the same one the member sees on
     * their other phone.
     */
    fun loadHistory() {
        if (loadedHistory) return
        loadedHistory = true

        viewModelScope.launch {
            val earlier = runCatching { history() }.getOrElse { emptyList() }
            if (earlier.isEmpty()) return@launch
            // Anything typed while this was loading stays where it was, at the
            // end of the conversation.
            _state.value = _state.value.copy(turns = earlier + _state.value.turns)
        }
    }

    private suspend fun history(): List<CoachTurn> {
        val token = Session.accessToken() ?: return emptyList()
        val response = http.get("${Config.supabaseUrl}/rest/v1/coach_messages") {
            header("apikey", Config.supabaseAnonKey)
            header("Authorization", "Bearer $token")
            // Newest first so the limit keeps the recent end of a long
            // conversation; reversed below for reading.
            parameter("select", "role,content,seq")
            parameter("order", "seq.desc")
            parameter("limit", "100")
        }
        return json.parseToJsonElement(response.bodyAsText()).jsonArray
            .map { row ->
                val obj = row.jsonObject
                CoachTurn(
                    text = obj["content"]?.jsonPrimitive?.content.orEmpty(),
                    fromCoach = obj["role"]?.jsonPrimitive?.content == "coach",
                )
            }
            .reversed()
    }

    fun ask(question: String) {
        if (question.isBlank() || _state.value.busy) return

        _state.value = _state.value.copy(
            turns = _state.value.turns + CoachTurn(question, fromCoach = false),
            busy = true,
        )

        viewModelScope.launch {
            val reply = runCatching { request(question) }
                .getOrElse { "Coach Landry isn't answering just now." }
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
