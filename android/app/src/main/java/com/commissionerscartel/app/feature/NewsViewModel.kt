package com.commissionerscartel.app.feature

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.commissionerscartel.app.data.Config
import com.commissionerscartel.app.data.NewsPost
import com.commissionerscartel.app.data.Supabase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface NewsState {
    data object Loading : NewsState
    data class Loaded(val posts: List<NewsPost>) : NewsState
    data class Failed(val message: String) : NewsState
}

class NewsViewModel : ViewModel() {
    private val _state = MutableStateFlow<NewsState>(NewsState.Loading)
    val state: StateFlow<NewsState> = _state.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            if (!Config.hasSupabase) {
                _state.value = NewsState.Failed(
                    "Supabase isn't configured. Add secrets.properties to the android project."
                )
                return@launch
            }
            _state.value = runCatching { Supabase.newsPosts(Config.currentSeason()) }
                .fold(
                    onSuccess = { NewsState.Loaded(it) },
                    onFailure = { NewsState.Failed(it.message ?: "Couldn't load league news.") },
                )
        }
    }
}
