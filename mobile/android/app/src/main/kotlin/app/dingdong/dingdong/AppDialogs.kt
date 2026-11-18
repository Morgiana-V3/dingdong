package app.dingdong.dingdong

import android.app.AlertDialog
import android.content.Context
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.WindowManager

object AppDialogs {
    fun builder(context: Context): AlertDialog.Builder =
        object : AlertDialog.Builder(ContextThemeWrapper(context, R.style.DingdongDialogTheme)) {
            override fun create(): AlertDialog = super.create().apply {
                window?.apply {
                    setGravity(Gravity.BOTTOM)
                    setWindowAnimations(R.style.DingdongSheetAnimation)
                }
                setOnShowListener {
                    window?.apply {
                        setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT)
                    }
                }
            }

            override fun show(): AlertDialog = create().apply { show() }
        }
}
