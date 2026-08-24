package com.commissionerscartel.app.data

import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.OTP
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map

/**
 * Sign-in, matching the iOS flow: a magic link is emailed, and the same email
 * carries a 6-digit code for anyone who opens it on a different device than the
 * app is installed on.
 *
 * Only addresses on the league invite list get a profile — that check lives in
 * Postgres, so signing in is not the same as being a member.
 */
object Session {
    private val auth get() = Supabase.client.auth

    /**
     * Emits whenever sign-in state changes, including the moment the stored
     * session finishes loading at launch.
     *
     * Screens must observe this rather than reading [isSignedIn] once: the
     * restore is asynchronous, so a one-shot check at startup sees "signed
     * out" and then never looks again.
     */
    val status: Flow<Boolean> = auth.sessionStatus
        .filter { it !is SessionStatus.Initializing }
        .map { it is SessionStatus.Authenticated }

    val email: String? get() = auth.currentUserOrNull()?.email
    val userId: String? get() = auth.currentUserOrNull()?.id
    val isSignedIn: Boolean get() = auth.currentUserOrNull() != null

    /** Sends the email. `createUser = false` keeps uninvited addresses out. */
    suspend fun sendCode(email: String) {
        auth.signInWith(OTP) {
            this.email = email.trim()
            createUser = true
        }
    }

    suspend fun verify(email: String, code: String) {
        auth.verifyEmailOtp(type = OtpType.Email.EMAIL, email = email.trim(), token = code.trim())
    }

    suspend fun signOut() = auth.signOut()

    /** The ESPN member id this account has claimed, or null. */
    suspend fun claimedTeamSwid(): String? = Supabase.claimedSwid(userId ?: return null)

    /** Claims an ESPN team. The RPC rejects a swid that is not in the league. */
    suspend fun claimTeam(swid: String) = Supabase.claimEspnTeam(swid)

    /**
     * True when this account has a profile row, which only an invited address
     * gets. Row level security means a non-member sees an empty table rather
     * than an error.
     */
    suspend fun isLeagueMember(): Boolean = runCatching {
        val id = userId ?: return false
        Supabase.profileExists(id)
    }.getOrDefault(false)
}
