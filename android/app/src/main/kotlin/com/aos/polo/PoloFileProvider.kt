package com.aos.polo

import androidx.core.content.FileProvider

/**
 * Lets Polo give another app temporary read access to a file the user picked.
 * It has its own class so it can't clash with the providers of other plugins.
 */
class PoloFileProvider : FileProvider()