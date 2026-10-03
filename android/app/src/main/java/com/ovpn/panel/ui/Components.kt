package com.ovpn.panel.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Dangerous
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Report
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ovpn.panel.core.BannerKind
import com.ovpn.panel.core.DS
import com.ovpn.panel.core.LocalPalette

/**
 * 共享 UI 组件库（Android 端）。
 *
 * 与 iOS `Sources/OVPNPanel/Components/Components.swift` 一一对应，
 * 视觉规格（圆角 / 尺寸 / 字号 / 颜色）全部取自 [DS] 与 [LocalPalette]，改动需三端同步。
 */

/** 按钮视觉样式（对应 iOS `AppButton.Style` 的 primary / accent / secondary / destructive） */
enum class ButtonStyleKind { Primary, Secondary, Destructive, Teal }

/** 与 iOS 一致的 15sp 半粗按钮文字 */
private val ButtonTextStyle = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold)

/**
 * 卡片容器，对应 iOS `AppCard`。
 * xl 圆角 + 1px 边框，默认卡片底色（可传 [background] 覆盖）。
 */
@Composable
fun AppCard(
    modifier: Modifier = Modifier,
    padding: Dp = DS.Size.cardPadding,
    background: Color? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val palette = LocalPalette.current
    val shape = RoundedCornerShape(DS.Radius.xl)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(background ?: palette.card)
            .border(1.dp, palette.border, shape)
            .padding(padding),
        content = content,
    )
}

/**
 * 彩色图标块，对应 iOS `IconTile`。
 * 圆角为边长的 30%，内部为 icon 色的低透明度渐变，图标居中。
 */
@Composable
fun IconTile(icon: ImageVector, color: Color, size: Dp = 34.dp) {
    val shape = RoundedCornerShape(size * 0.3f)
    Box(
        modifier = Modifier
            .size(size)
            .clip(shape)
            .background(
                Brush.linearGradient(
                    colors = listOf(color.copy(alpha = 0.22f), color.copy(alpha = 0.12f)),
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(size * 0.46f),
        )
    }
}

/** 区块标题，对应 iOS `SectionHeader`：标题 + 可选副标题。 */
@Composable
fun SectionHeader(title: String, subtitle: String? = null) {
    val palette = LocalPalette.current
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(text = title, style = DS.Font.section, color = palette.foreground)
        if (subtitle != null) {
            Text(text = subtitle, style = DS.Font.caption, color = palette.mutedForeground)
        }
    }
}

/** 胶囊状态徽章，对应 iOS `StatusBadge`。 */
@Composable
fun StatusBadge(text: String, background: Color, foreground: Color) {
    Text(
        text = text,
        style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium),
        color = foreground,
        modifier = Modifier
            .clip(CircleShape)
            .background(background)
            .padding(horizontal = 7.dp, vertical = 3.dp),
    )
}

/** 键值信息行，对应 iOS `InfoRow`：左侧标签、右侧数值（默认次级文字色）。 */
@Composable
fun InfoRow(label: String, value: String, valueColor: Color? = null) {
    val palette = LocalPalette.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
    ) {
        Text(text = label, style = DS.Font.bodySmall, color = palette.mutedForeground)
        Spacer(Modifier.width(12.dp))
        Text(
            text = value,
            style = DS.Font.value,
            color = valueColor ?: palette.secondaryText,
            textAlign = TextAlign.End,
            modifier = Modifier.weight(1f),
        )
    }
}

/**
 * 主操作按钮，对应 iOS `AppButton`。
 * [ButtonStyleKind.Primary] / [ButtonStyleKind.Teal] / [ButtonStyleKind.Destructive] 使用品牌渐变，
 * [ButtonStyleKind.Secondary] 使用次级底色；[loading] 时以圆形进度替代前置图标。
 */
@Composable
fun AppButton(
    title: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    style: ButtonStyleKind = ButtonStyleKind.Primary,
    height: Dp = DS.Size.buttonHeight,
    loading: Boolean = false,
    disabled: Boolean = false,
    onClick: () -> Unit,
) {
    val palette = LocalPalette.current
    val shape = RoundedCornerShape(DS.Radius.lg)
    val enabled = !disabled && !loading

    val fg = when (style) {
        ButtonStyleKind.Primary, ButtonStyleKind.Destructive, ButtonStyleKind.Teal -> Color.White
        ButtonStyleKind.Secondary -> palette.secondaryForeground
    }
    val brush: Brush? = when (style) {
        ButtonStyleKind.Primary -> palette.accentGradient
        ButtonStyleKind.Teal -> palette.tealGradient
        ButtonStyleKind.Destructive -> palette.dangerGradient
        ButtonStyleKind.Secondary -> null
    }
    val shadowColor: Color? = when (style) {
        ButtonStyleKind.Primary -> DS.Brand.green.copy(alpha = 0.28f)
        ButtonStyleKind.Teal -> DS.Brand.teal.copy(alpha = 0.26f)
        ButtonStyleKind.Destructive -> DS.Brand.red.copy(alpha = 0.24f)
        ButtonStyleKind.Secondary -> null
    }

    val interactionSource = remember { MutableInteractionSource() }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .alpha(if (disabled) 0.5f else 1f)
            .then(
                if (shadowColor != null) {
                    Modifier.shadow(
                        elevation = 8.dp,
                        shape = shape,
                        ambientColor = shadowColor,
                        spotColor = shadowColor,
                    )
                } else {
                    Modifier
                },
            )
            .clip(shape)
            .then(if (brush != null) Modifier.background(brush) else Modifier.background(palette.secondary))
            .then(if (enabled) Modifier.pressableScale() else Modifier)
            .then(
                if (enabled) {
                    Modifier.clickable(
                        interactionSource = interactionSource,
                        indication = null,
                        onClick = onClick,
                    )
                } else {
                    Modifier
                },
            ),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    color = fg,
                    strokeWidth = 2.dp,
                )
            } else if (icon != null) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = fg,
                    modifier = Modifier.size(14.dp),
                )
            }
            Text(text = title, style = ButtonTextStyle, color = fg)
        }
    }
}

/**
 * 文本输入框，对应 iOS `AppTextField`。
 * 标签在上（bodySmall / secondaryText），字段 42dp 高、背景填充 + 1px 边框、lg 圆角。
 * [enabled] 为 false 时外观不变但不可交互（对齐 iOS 禁用态）。
 */
@Composable
fun AppTextField(
    title: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    secure: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    enabled: Boolean = true,
    singleLine: Boolean = true,
) {
    val palette = LocalPalette.current
    val shape = RoundedCornerShape(DS.Radius.lg)
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(text = title, style = DS.Font.bodySmall, color = palette.secondaryText)
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            enabled = enabled,
            singleLine = singleLine,
            textStyle = DS.Font.body.copy(color = palette.foreground),
            cursorBrush = SolidColor(palette.primary),
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
            modifier = Modifier
                .fillMaxWidth()
                .height(DS.Size.inputHeight)
                .clip(shape)
                .background(palette.background)
                .border(1.dp, palette.border, shape),
            decorationBox = { innerTextField ->
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 12.dp),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    if (value.isEmpty()) {
                        Text(
                            text = placeholder,
                            style = DS.Font.body,
                            color = palette.mutedForeground,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    innerTextField()
                }
            },
        )
    }
}

/**
 * 只读字段，对应 iOS `ReadOnlyField`。
 * 不可点击、不可编辑；muted 60% 透明底色 + 1px 边框 + lg 圆角。
 */
@Composable
fun ReadOnlyField(title: String, value: String = "", masked: Boolean = false) {
    val palette = LocalPalette.current
    val shape = RoundedCornerShape(DS.Radius.lg)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(text = title, style = DS.Font.bodySmall, color = palette.secondaryText)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(DS.Size.inputHeight)
                .clip(shape)
                .background(palette.muted.copy(alpha = 0.6f))
                .border(1.dp, palette.border, shape)
                .padding(horizontal = 12.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            Text(
                text = if (masked) "••••••••" else value,
                style = DS.Font.body,
                color = palette.mutedForeground,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/**
 * 分段切换控件，对应 iOS `SegmentedTabs`。
 * muted 胶囊底、选中项使用 card 底色 + 轻微阴影，内边距 2dp、md 圆角。
 */
@Composable
fun SegmentedTabs(
    items: List<String>,
    selection: Int,
    onSelect: (Int) -> Unit,
    segmentWidth: Dp = 82.dp,
) {
    val palette = LocalPalette.current
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(DS.Radius.md))
            .background(palette.muted)
            .padding(2.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        items.forEachIndexed { index, item ->
            val selected = index == selection
            val itemShape = RoundedCornerShape(DS.Radius.sm)
            val interactionSource = remember { MutableInteractionSource() }
            Box(
                modifier = Modifier
                    .width(segmentWidth)
                    .height(28.dp)
                    .then(
                        if (selected) {
                            Modifier
                                .shadow(
                                    elevation = 3.dp,
                                    shape = itemShape,
                                    ambientColor = Color.Black.copy(alpha = 0.08f),
                                    spotColor = Color.Black.copy(alpha = 0.08f),
                                )
                                .clip(itemShape)
                                .background(palette.card)
                        } else {
                            Modifier
                        },
                    )
                    .pressableScale(scale = 0.96f)
                    .clickable(
                        interactionSource = interactionSource,
                        indication = null,
                    ) { onSelect(index) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = item,
                    style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold),
                    color = if (selected) palette.primary else palette.mutedForeground,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/**
 * 页面内提示条，对应 iOS `BannerBar`：按类型取状态底色，md 圆角、无边框，左侧小图标。
 * 颜色与图标严格对齐 iOS 实现（error → offlineBg/offlineText 等）。
 */
@Composable
fun BannerBar(
    message: String,
    kind: BannerKind = BannerKind.Error,
    modifier: Modifier = Modifier,
    actionTitle: String? = null,
    onAction: (() -> Unit)? = null,
) {
    val palette = LocalPalette.current
    val (bg, fg, icon) = when (kind) {
        BannerKind.Error -> Triple(palette.offlineBg, palette.offlineText, Icons.Outlined.ErrorOutline)
        BannerKind.Warning -> Triple(palette.warningBg, palette.warningText, Icons.Outlined.Info)
        BannerKind.Success -> Triple(palette.onlineBg, palette.onlineText, Icons.Outlined.CheckCircle)
        BannerKind.Info -> Triple(palette.muted, palette.secondaryText, Icons.Outlined.Info)
    }
    val shape = RoundedCornerShape(DS.Radius.md)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(bg)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = fg,
            modifier = Modifier.size(13.dp),
        )
        Text(
            text = message,
            style = DS.Font.caption,
            color = fg,
            modifier = Modifier.weight(1f),
        )
        if (actionTitle != null && onAction != null) {
            val actionSource = remember { MutableInteractionSource() }
            Text(
                text = actionTitle,
                style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold),
                color = fg,
                modifier = Modifier
                    .clip(RoundedCornerShape(DS.Radius.sm))
                    .clickable(interactionSource = actionSource, indication = null) { onAction() }
                    .padding(horizontal = 4.dp, vertical = 1.dp),
            )
        }
    }
}

/**
 * 富提示卡片，对应 iOS `ToastCard`：按 kind 取 sonner 风格配色 + 1px 边框 + 阴影。
 * App 顶部的全局提示浮层使用本组件。
 */
@Composable
fun ToastCard(message: String, kind: BannerKind = BannerKind.Info, modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    val style = palette.toastStyle(kind)
    val icon = when (kind) {
        BannerKind.Success -> Icons.Filled.CheckCircle
        BannerKind.Error -> Icons.Filled.Dangerous
        BannerKind.Warning -> Icons.Filled.Warning
        BannerKind.Info -> Icons.Filled.Info
    }
    val shape = RoundedCornerShape(DS.Radius.lg)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .shadow(elevation = 8.dp, shape = shape, ambientColor = Color.Black.copy(alpha = 0.10f), spotColor = Color.Black.copy(alpha = 0.10f))
            .clip(shape)
            .background(style.background)
            .border(1.dp, style.border, shape)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = style.foreground,
            modifier = Modifier.size(15.dp),
        )
        Text(
            text = message,
            style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium),
            color = style.foreground,
            modifier = Modifier.weight(1f),
        )
    }
}

/**
 * 页面骨架，对应 iOS `NavigationStack` + `.navigationTitle(...).navigationBarTitleDisplayMode(.large)`。
 * 提供：页面底色、大标题、可选返回按钮（主题绿）、内容区。
 * [onBack] 为 null 时表示 Tab 根页面（不显示返回按钮）。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ScreenScaffold(
    title: String,
    onBack: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    trailing: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    val palette = LocalPalette.current
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(palette.background),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = DS.Size.pagePadding)
                .padding(top = 10.dp, bottom = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (onBack != null) {
                val interactionSource = remember { MutableInteractionSource() }
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(DS.Radius.md))
                        .clickable(interactionSource = interactionSource, indication = null) { onBack() }
                        .pressableScale(scale = 0.94f)
                        .padding(vertical = 4.dp, horizontal = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Icon(
                        imageVector = Icons.Filled.ChevronLeft,
                        contentDescription = "返回",
                        tint = palette.primary,
                        modifier = Modifier.size(22.dp),
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            trailing()
        }
        Text(
            text = title,
            style = DS.Font.title,
            color = palette.foreground,
            modifier = Modifier.padding(horizontal = DS.Size.pagePadding).padding(top = 2.dp, bottom = 6.dp),
        )
        Column(modifier = Modifier.weight(1f)) { content() }
    }
}

/** 列表行，对应 iOS `MenuRow`。
 * 34dp 图标块 + 标题/副标题 + 可选徽章 + 右箭头，行高 58dp。
 */
@Composable
fun MenuRow(
    icon: ImageVector,
    iconColor: Color,
    title: String,
    subtitle: String? = null,
    badge: String? = null,
    showChevron: Boolean = true,
    onClick: (() -> Unit)? = null,
) {
    val palette = LocalPalette.current
    val interactionSource = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(58.dp)
            .then(
                if (onClick != null) {
                    Modifier.clickable(
                        interactionSource = interactionSource,
                        indication = null,
                        onClick = onClick,
                    )
                } else {
                    Modifier
                },
            )
            .pressableScale()
            .padding(horizontal = DS.Size.cardPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        IconTile(icon = icon, color = iconColor)
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(text = title, style = DS.Font.body, color = palette.foreground)
            if (!subtitle.isNullOrEmpty()) {
                Text(text = subtitle, style = DS.Font.caption, color = palette.mutedForeground)
            }
        }
        if (!badge.isNullOrEmpty()) {
            StatusBadge(
                text = badge,
                background = iconColor.copy(alpha = 0.14f),
                foreground = iconColor,
            )
        }
        if (showChevron) {
            Icon(
                imageVector = Icons.Filled.ChevronRight,
                contentDescription = null,
                tint = palette.mutedForeground.copy(alpha = 0.8f),
                modifier = Modifier.size(12.dp),
            )
        }
    }
}

/** 底部浮层提示，对应 iOS `ToastView`：白字、82% 黑底、md 圆角。 */
@Composable
fun ToastView(message: String) {
    Text(
        text = message,
        style = DS.Font.bodySmall,
        color = Color.White,
        modifier = Modifier
            .clip(RoundedCornerShape(DS.Radius.md))
            .background(Color.Black.copy(alpha = 0.82f))
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .padding(bottom = 28.dp),
    )
}

/** 加载中占位块，对应 iOS `LoadingBlock`：圆形进度 + 文案，垂直内边距 28dp。 */
@Composable
fun LoadingBlock(text: String) {
    val palette = LocalPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 28.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(
            modifier = Modifier.size(20.dp),
            color = palette.primary,
            strokeWidth = 2.dp,
        )
        Spacer(Modifier.width(8.dp))
        Text(text = text, style = DS.Font.bodySmall, color = palette.mutedForeground)
    }
}

/** 空状态提示，对应 iOS `EmptyHint`：图标 + 标题 + 可选副标题，垂直内边距 32dp。 */
@Composable
fun EmptyHint(icon: ImageVector, title: String, subtitle: String? = null) {
    val palette = LocalPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = palette.mutedForeground,
            modifier = Modifier.size(26.dp),
        )
        Text(text = title, style = DS.Font.body, color = palette.mutedForeground)
        if (subtitle != null) {
            Text(text = subtitle, style = DS.Font.caption, color = palette.mutedForeground)
        }
    }
}

/**
 * 步骤徽章（Android 端新增，iOS 无同名组件）。
 * 使用主色渐变背景的胶囊标签，用于分步流程标识当前步骤。
 */
@Composable
fun StepBadge(value: String) {
    val palette = LocalPalette.current
    Text(
        text = value,
        style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold),
        color = Color.White,
        modifier = Modifier
            .clip(RoundedCornerShape(DS.Radius.sm))
            .background(palette.accentGradient)
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

/**
 * 连接进度圆环，对应 iOS `ConnectRing` 的圆环绘制。
 * 从 -90°（12 点方向）开始顺时针绘制渐变弧线，[progress] 取 0f..1f；
 * [content] 叠加在圆环中央（用于计时 / 状态文字）。
 */
@Composable
fun AppProgressRing(
    progress: Float,
    colors: List<Color>,
    modifier: Modifier = Modifier,
    trackColor: Color,
    strokeWidth: Dp = 10.dp,
    content: @Composable () -> Unit = {},
) {
    val safeProgress = progress.coerceIn(0f, 1f)
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val strokePx = strokeWidth.toPx()
            val arcSize = Size(size.width - strokePx, size.height - strokePx)
            val topLeft = Offset(strokePx / 2f, strokePx / 2f)
            val arcStyle = Stroke(width = strokePx, cap = StrokeCap.Round)

            // 底环
            drawArc(
                color = trackColor,
                startAngle = -90f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = arcStyle,
            )

            // 渐变主环：先旋转 -90°，使 sweepGradient 的起点对齐 12 点方向
            if (safeProgress > 0f && colors.isNotEmpty()) {
                rotate(-90f) {
                    drawArc(
                        brush = Brush.sweepGradient(colors = colors, center = center),
                        startAngle = 0f,
                        sweepAngle = 360f * safeProgress,
                        useCenter = false,
                        topLeft = topLeft,
                        size = arcSize,
                        style = arcStyle,
                    )
                }
            }
        }
        content()
    }
}

/**
 * 按压缩放反馈，对应 iOS `PressableStyle`。
 * 按下时缩放至 [scale] 并将不透明度降至 0.9，使用弹簧动画；
 * 通过 [PointerEventPass.Initial] 只观察不消费手势，因此不会吞掉外部 clickable 的点击，
 * 也不产生 Material 水波纹（与 SwiftUI 自定义按压样式一致）。
 */
fun Modifier.pressableScale(scale: Float = 0.97f): Modifier = composed {
    var pressed by remember { mutableStateOf(false) }
    val animatedScale by animateFloatAsState(
        targetValue = if (pressed) scale else 1f,
        animationSpec = spring(
            dampingRatio = 0.7f,
            stiffness = Spring.StiffnessMedium,
        ),
        label = "pressableScale",
    )
    val animatedAlpha by animateFloatAsState(
        targetValue = if (pressed) 0.9f else 1f,
        animationSpec = spring(
            dampingRatio = 0.7f,
            stiffness = Spring.StiffnessMedium,
        ),
        label = "pressableAlpha",
    )
    this
        .graphicsLayer {
            scaleX = animatedScale
            scaleY = animatedScale
            alpha = animatedAlpha
        }
        .pointerInput(Unit) {
            awaitEachGesture {
                try {
                    awaitPointerEvent(PointerEventPass.Initial)
                    pressed = true
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        if (event.changes.none { it.pressed }) break
                    }
                } finally {
                    pressed = false
                }
            }
        }
}