import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  Sequence,
  Img,
  staticFile,
  Audio,
} from "remotion";

// 颜色配置
const colors = {
  background: "#0d1117",
  text: "#ffffff",
  textMuted: "rgba(255, 255, 255, 0.6)",
  accent: "#8b5cf6",
  green: "#10b981",
  claudeOrange: "#d97706",
};

// 打字机效果的光标
const Cursor: React.FC<{ visible?: boolean }> = ({ visible = true }) => {
  const frame = useCurrentFrame();
  const blink = Math.floor(frame / 8) % 2 === 0;

  return (
    <span
      style={{
        display: "inline-block",
        width: 3,
        height: 28,
        background: colors.claudeOrange,
        marginLeft: 2,
        verticalAlign: "middle",
        opacity: visible && blink ? 1 : 0,
      }}
    />
  );
};

// 横版场景1：转场 - 黑屏 + 图标闪现
const Scene1_Transition: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const blackScreenEnd = 15;
  const isBlackScreen = frame < blackScreenEnd;

  const iconScale = spring({
    frame: frame - blackScreenEnd,
    fps,
    config: { damping: 10, stiffness: 100 },
  });

  const iconOpacity = interpolate(
    frame,
    [blackScreenEnd, blackScreenEnd + 10],
    [0, 1],
    { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
  );

  const glowIntensity = 0.3 + Math.sin(frame * 0.2) * 0.2;

  const textOpacity = interpolate(frame, [40, 55], [0, 1], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
  });

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {!isBlackScreen && (
        <>
          {/* 紫色光晕背景 */}
          <div
            style={{
              position: "absolute",
              top: "50%",
              left: "50%",
              width: 500,
              height: 500,
              marginTop: -250,
              marginLeft: -250,
              background: `radial-gradient(circle, rgba(139, 92, 246, ${glowIntensity}) 0%, transparent 70%)`,
              filter: "blur(60px)",
            }}
          />

          {/* App 图标 */}
          <div
            style={{
              position: "absolute",
              top: "50%",
              left: "50%",
              transform: `translate(-50%, -50%) scale(${Math.max(0, iconScale)})`,
              opacity: iconOpacity,
            }}
          >
            <Img
              src={staticFile("icon_512x512.png")}
              style={{
                width: 150,
                height: 150,
                borderRadius: 35,
                boxShadow: "0 0 80px rgba(139, 92, 246, 0.6)",
              }}
            />
          </div>

          {/* 标题和副标题 */}
          <div
            style={{
              position: "absolute",
              bottom: 180,
              left: "50%",
              transform: "translateX(-50%)",
              opacity: textOpacity,
              textAlign: "center",
            }}
          >
            <h2
              style={{
                fontSize: 48,
                fontWeight: 700,
                color: colors.text,
                margin: 0,
                fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
              }}
            >
              Nano Typeless
            </h2>
            <p
              style={{
                fontSize: 28,
                color: colors.textMuted,
                marginTop: 12,
                fontWeight: 500,
                letterSpacing: "6px",
              }}
            >
              PRESS. SPEAK.
            </p>
          </div>
        </>
      )}
    </AbsoluteFill>
  );
};

// 横版场景2：核心演示 - Claude Code + 顶部 HUD
const Scene2_Demo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const voiceText = "帮我配置 GitHub Actions 自动部署";

  // 时间轴
  const claudeAppearFrame = 0;
  const fnKeyPressFrame = 20;
  const listeningEndFrame = 105;
  const hudFadeOutEndFrame = 112;
  const textAppearFrame = 119;
  const textTypingSpeed = 8;

  // 文字打字效果
  const typedLength = frame > textAppearFrame
    ? Math.floor((frame - textAppearFrame) * textTypingSpeed)
    : 0;
  const displayText = voiceText.slice(0, Math.min(typedLength, voiceText.length));
  const isTypingComplete = typedLength >= voiceText.length;

  const isRecording = frame > fnKeyPressFrame && frame < listeningEndFrame;

  // Claude Code 界面淡入
  const claudeOpacity = interpolate(
    frame,
    [claudeAppearFrame, claudeAppearFrame + 15],
    [0, 1],
    { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
  );

  // HUD 从顶部滑入动画
  const hudSlideIn = spring({
    frame: frame - fnKeyPressFrame,
    fps,
    config: { damping: 15, stiffness: 120 },
  });

  // HUD 滑出动画
  const hudSlideOut = frame > listeningEndFrame
    ? interpolate(frame, [listeningEndFrame, hudFadeOutEndFrame], [0, -80], {
        extrapolateRight: "clamp",
      })
    : 0;

  const hudY = interpolate(hudSlideIn, [0, 1], [-80, 50]) + hudSlideOut;

  const hudOpacity = interpolate(
    frame,
    [fnKeyPressFrame, fnKeyPressFrame + 8, listeningEndFrame - 3, hudFadeOutEndFrame],
    [0, 1, 1, 0],
    { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
  );

  return (
    <AbsoluteFill style={{ background: "#1a1a2e" }}>
      {/* Claude Code 界面 */}
      <div
        style={{
          position: "absolute",
          top: 60,
          left: 80,
          right: 80,
          bottom: 60,
          opacity: claudeOpacity,
          background: "#0d1117",
          borderRadius: 12,
          overflow: "hidden",
          boxShadow: "0 20px 60px rgba(0,0,0,0.5)",
          border: "1px solid rgba(255,255,255,0.1)",
        }}
      >
        <div
          style={{
            padding: 40,
            fontFamily: "SF Mono, Menlo, monospace",
            color: colors.text,
          }}
        >
          {/* 主框体 */}
          <div
            style={{
              border: "1px solid rgba(255,255,255,0.2)",
              borderRadius: 8,
              overflow: "hidden",
            }}
          >
            {/* 上边框 */}
            <div
              style={{
                borderBottom: "1px solid rgba(255,255,255,0.2)",
                padding: "16px 24px",
                display: "flex",
                justifyContent: "center",
                fontSize: 14,
                color: "rgba(255,255,255,0.5)",
              }}
            >
              ─── Claude Code ───
            </div>

            {/* 内容区域 - 两栏布局 */}
            <div style={{ display: "flex" }}>
              {/* 左栏 - 欢迎信息 */}
              <div
                style={{
                  flex: 1,
                  padding: "32px 40px",
                  borderRight: "1px solid rgba(255,255,255,0.2)",
                  textAlign: "center",
                }}
              >
                <p style={{ fontSize: 18, marginBottom: 24, color: "rgba(255,255,255,0.8)" }}>
                  Welcome back!
                </p>

                {/* Claude Logo - ASCII Art 风格 */}
                <div style={{ fontSize: 20, lineHeight: 1.2, marginBottom: 24, color: "#d97706" }}>
                  <p style={{ margin: 0 }}>▐▛███▜▌</p>
                  <p style={{ margin: 0 }}>▝▜█████▛▘</p>
                </div>

                <p style={{ fontSize: 12, color: "rgba(255,255,255,0.5)", marginBottom: 8 }}>
                  claude-opus-4.5 · API Usage Billing
                </p>
                <p style={{ fontSize: 12, color: "rgba(255,255,255,0.5)" }}>
                  ~/Github/typeless
                </p>
              </div>

              {/* 右栏 - Tips */}
              <div style={{ flex: 1, padding: "32px 40px" }}>
                <p style={{ fontSize: 13, color: "rgba(255,255,255,0.6)", marginBottom: 16 }}>
                  Tips for getting started
                </p>
                <p style={{ fontSize: 12, color: "rgba(255,255,255,0.4)", marginBottom: 24 }}>
                  Run /init to create a CLAUDE.md file with instructions for Claude
                </p>
                <div style={{ borderTop: "1px solid rgba(255,255,255,0.1)", marginBottom: 24 }} />
                <p style={{ fontSize: 13, color: "rgba(255,255,255,0.6)", marginBottom: 16 }}>
                  Recent activity
                </p>
                <p style={{ fontSize: 12, color: "rgba(255,255,255,0.4)" }}>
                  No recent activity
                </p>
              </div>
            </div>

            {/* 底部边框 */}
            <div
              style={{
                borderTop: "1px solid rgba(255,255,255,0.2)",
                padding: "12px 24px",
              }}
            />
          </div>

          {/* 语音输入区域 */}
          <div
            style={{
              marginTop: 24,
              padding: "20px 24px",
              background: "rgba(139, 92, 246, 0.1)",
              borderRadius: 8,
              border: "1px solid rgba(139, 92, 246, 0.3)",
              height: 70,
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <span style={{ color: "#8b5cf6", fontSize: 16 }}>❯</span>
              <p
                style={{
                  fontSize: 18,
                  color: colors.text,
                  margin: 0,
                  lineHeight: 1.6,
                  fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
                }}
              >
                {frame > textAppearFrame ? (
                  <>
                    {displayText}
                    {!isTypingComplete && <Cursor />}
                  </>
                ) : (
                  <Cursor />
                )}
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* 顶部 HUD：Typeless 录音指示器 */}
      {frame > fnKeyPressFrame && frame < hudFadeOutEndFrame + 5 && (
        <div
          style={{
            position: "absolute",
            top: hudY,
            left: "50%",
            transform: "translateX(-50%)",
            opacity: hudOpacity,
            background: "rgba(25, 25, 30, 0.92)",
            backdropFilter: "blur(20px)",
            borderRadius: 40,
            padding: "14px 28px",
            boxShadow: "0 8px 32px rgba(0,0,0,0.4), 0 0 0 1px rgba(255,255,255,0.08)",
            display: "flex",
            alignItems: "center",
            gap: 18,
          }}
        >
          {/* 波形动画 */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 4,
              height: 28,
            }}
          >
            {Array.from({ length: 7 }).map((_, i) => {
              const centerIndex = 3;
              const distanceFromCenter = Math.abs(i - centerIndex);
              const baseHeight = Math.max(10, 24 - distanceFromCenter * 4);
              const amplitude = Math.max(4, 10 - distanceFromCenter * 2);
              const frequency = 0.4 + (i % 3) * 0.1;
              const phase = i * 0.7;
              const barHeight = isRecording
                ? baseHeight + Math.sin((frame * frequency) + phase) * amplitude
                : 8;

              return (
                <div
                  key={i}
                  style={{
                    width: 4,
                    height: Math.max(8, barHeight),
                    background: isRecording
                      ? "linear-gradient(180deg, rgba(255,255,255,0.95), rgba(255,255,255,0.5))"
                      : "rgba(255,255,255,0.3)",
                    borderRadius: 2,
                  }}
                />
              );
            })}
          </div>

          {/* 正在聆听文字 */}
          <p
            style={{
              fontSize: 16,
              color: "rgba(255,255,255,0.85)",
              margin: 0,
              fontWeight: 500,
              fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
              whiteSpace: "nowrap",
            }}
          >
            正在聆听...
          </p>
        </div>
      )}

      {/* 底部字幕 */}
      {frame > 90 && (
        <div
          style={{
            position: "absolute",
            bottom: 40,
            left: "50%",
            transform: "translateX(-50%)",
            background: "rgba(0, 0, 0, 0.85)",
            padding: "12px 24px",
            borderRadius: 8,
            opacity: interpolate(frame, [90, 105], [0, 1], {
              extrapolateRight: "clamp",
            }),
          }}
        >
          <p style={{ fontSize: 20, color: colors.text, margin: 0 }}>
            🎤 语音秒变代码
          </p>
        </div>
      )}
    </AbsoluteFill>
  );
};

// 横版场景3：三个卖点 - 全屏闪切
const Scene3_Features: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // 每个卖点 60 帧（2秒）
  const featureIndex = Math.floor(frame / 60);

  const features = [
    {
      icon: "lock.png",
      title: "100% Local",
      subtitle: "纯本地运行",
      desc: "数据永不上传",
      color: "#10b981",
    },
    {
      icon: "high-voltage.png",
      title: "Instant",
      subtitle: "极速响应",
      desc: "毫秒级识别",
      color: "#f59e0b",
    },
    {
      icon: "globe-with-meridians.png",
      title: "Mixed",
      subtitle: "中英文混合",
      desc: "智能语言切换",
      color: "#8b5cf6",
    },
  ];

  const currentFeature = features[Math.min(featureIndex, features.length - 1)];
  const featureFrame = frame % 60;

  const scale = spring({
    frame: featureFrame,
    fps,
    config: { damping: 12 },
  });

  const opacity = interpolate(featureFrame, [0, 12, 48, 60], [0, 1, 1, 0], {
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {/* 背景光晕 */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `radial-gradient(circle at 50% 50%, ${currentFeature.color}25 0%, transparent 60%)`,
        }}
      />

      <div
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          transform: `translate(-50%, -50%) scale(${Math.max(0, scale)})`,
          opacity,
          textAlign: "center",
        }}
      >
        {/* 图标 */}
        <Img
          src={staticFile(currentFeature.icon)}
          style={{
            width: 120,
            height: 120,
            marginBottom: 32,
          }}
        />

        {/* 主标题 */}
        <h1
          style={{
            fontSize: 72,
            fontWeight: 700,
            color: currentFeature.color,
            margin: 0,
            fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
            textShadow: `0 0 50px ${currentFeature.color}80`,
          }}
        >
          {currentFeature.title}
        </h1>

        {/* 副标题 */}
        <p
          style={{
            fontSize: 36,
            color: colors.text,
            marginTop: 16,
            fontWeight: 500,
          }}
        >
          {currentFeature.subtitle}
        </p>

        {/* 描述 */}
        <p
          style={{
            fontSize: 24,
            color: colors.textMuted,
            marginTop: 12,
          }}
        >
          {currentFeature.desc}
        </p>
      </div>

      {/* 进度指示器 */}
      <div
        style={{
          position: "absolute",
          bottom: 60,
          left: "50%",
          transform: "translateX(-50%)",
          display: "flex",
          gap: 12,
        }}
      >
        {features.map((_, i) => (
          <div
            key={i}
            style={{
              width: 40,
              height: 6,
              borderRadius: 3,
              background:
                i === featureIndex
                  ? currentFeature.color
                  : "rgba(255,255,255,0.2)",
            }}
          />
        ))}
      </div>
    </AbsoluteFill>
  );
};

// 横版场景4：CTA - 全屏
const Scene4_CTA: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const titleScale = spring({
    frame,
    fps,
    config: { damping: 12 },
  });

  const titleOpacity = interpolate(frame, [0, 20], [0, 1], {
    extrapolateRight: "clamp",
  });

  const commandOpacity = interpolate(frame, [30, 50], [0, 1], {
    extrapolateRight: "clamp",
  });

  const codeOpacity = interpolate(frame, [60, 80], [0, 1], {
    extrapolateRight: "clamp",
  });

  // 背景代码滚动效果
  const codeScrollY = frame * 0.5;

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {/* 背景代码 - 语法高亮 */}
      <div
        style={{
          position: "absolute",
          right: 0,
          top: 0,
          width: "50%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          opacity: codeOpacity * 0.85,
          overflow: "hidden",
        }}
      >
        <pre
          style={{
            fontFamily: "SF Mono, Menlo, monospace",
            fontSize: 16,
            lineHeight: 1.8,
            padding: 40,
            margin: 0,
            transform: `translateY(-${codeScrollY}px)`,
          }}
        >
          <span style={{ color: "#6b7280" }}>{"// GitHub Actions workflow generated by voice\n"}</span>
          <span style={{ color: "#f472b6" }}>name</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#a5f3fc" }}>Deploy to Production</span>{"\n\n"}
          <span style={{ color: "#f472b6" }}>on</span><span style={{ color: "#9ca3af" }}>:</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"  push"}</span><span style={{ color: "#9ca3af" }}>:</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"    branches"}</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#fde68a" }}>{"[ main ]"}</span>{"\n\n"}
          <span style={{ color: "#f472b6" }}>jobs</span><span style={{ color: "#9ca3af" }}>:</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"  deploy"}</span><span style={{ color: "#9ca3af" }}>:</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"    runs-on"}</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#a5f3fc" }}>ubuntu-latest</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"    steps"}</span><span style={{ color: "#9ca3af" }}>:</span>{"\n"}
          <span style={{ color: "#9ca3af" }}>{"      - "}</span><span style={{ color: "#c4b5fd" }}>uses</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#a5f3fc" }}>actions/checkout@v4</span>{"\n\n"}
          <span style={{ color: "#9ca3af" }}>{"      - "}</span><span style={{ color: "#c4b5fd" }}>name</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#a5f3fc" }}>Setup Node.js</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"        uses"}</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#a5f3fc" }}>actions/setup-node@v4</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"        with"}</span><span style={{ color: "#9ca3af" }}>:</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"          node-version"}</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#fde68a" }}>{"'20'"}</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"          cache"}</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#fde68a" }}>{"'npm'"}</span>{"\n\n"}
          <span style={{ color: "#9ca3af" }}>{"      - "}</span><span style={{ color: "#c4b5fd" }}>name</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#a5f3fc" }}>Install dependencies</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"        run"}</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#10b981" }}>npm ci</span>{"\n\n"}
          <span style={{ color: "#9ca3af" }}>{"      - "}</span><span style={{ color: "#c4b5fd" }}>name</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#a5f3fc" }}>Build</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"        run"}</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#10b981" }}>npm run build</span>{"\n\n"}
          <span style={{ color: "#9ca3af" }}>{"      - "}</span><span style={{ color: "#c4b5fd" }}>name</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#a5f3fc" }}>Deploy</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"        uses"}</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#a5f3fc" }}>cloudflare/wrangler-action@v3</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"        with"}</span><span style={{ color: "#9ca3af" }}>:</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"          apiToken"}</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#fbbf24" }}>{"${{ secrets.CF_API_TOKEN }}"}</span>{"\n"}
          <span style={{ color: "#c4b5fd" }}>{"          command"}</span><span style={{ color: "#9ca3af" }}>: </span><span style={{ color: "#10b981" }}>pages deploy dist</span>
        </pre>
      </div>

      {/* 紫色光晕 */}
      <div
        style={{
          position: "absolute",
          left: "25%",
          top: "50%",
          width: 500,
          height: 500,
          marginLeft: -250,
          marginTop: -250,
          background: "radial-gradient(circle, rgba(139, 92, 246, 0.3) 0%, transparent 60%)",
          filter: "blur(80px)",
        }}
      />

      {/* 主要内容 */}
      <div
        style={{
          position: "absolute",
          left: 80,
          top: "50%",
          transform: "translateY(-50%)",
          maxWidth: 600,
        }}
      >
        {/* Logo + 标题 */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 20,
            opacity: titleOpacity,
            transform: `scale(${Math.max(0, titleScale)})`,
            marginBottom: 32,
          }}
        >
          <Img
            src={staticFile("icon_512x512.png")}
            style={{
              width: 72,
              height: 72,
              borderRadius: 18,
              boxShadow: "0 0 40px rgba(139, 92, 246, 0.4)",
            }}
          />
          <div>
            <h1
              style={{
                fontSize: 48,
                fontWeight: 700,
                color: colors.text,
                margin: 0,
                fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
              }}
            >
              Nano Typeless
            </h1>
            <p
              style={{
                fontSize: 18,
                color: colors.textMuted,
                margin: 0,
                marginTop: 4,
              }}
            >
              别让打字限制你的代码灵感
            </p>
          </div>
        </div>

        {/* 安装命令 */}
        <div
          style={{
            opacity: commandOpacity,
            background: "rgba(255, 255, 255, 0.05)",
            borderRadius: 12,
            padding: "20px 28px",
            border: "1px solid rgba(255, 255, 255, 0.1)",
            marginBottom: 20,
          }}
        >
          <p
            style={{
              fontSize: 13,
              color: colors.textMuted,
              margin: 0,
              marginBottom: 10,
            }}
          >
            立即安装
          </p>
          <code
            style={{
              fontSize: 18,
              color: colors.green,
              fontFamily: "SF Mono, Menlo, monospace",
              display: "block",
              marginBottom: 6,
            }}
          >
            brew tap ZhaoChaoqun/typeless
          </code>
          <code
            style={{
              fontSize: 18,
              color: colors.green,
              fontFamily: "SF Mono, Menlo, monospace",
            }}
          >
            brew install --cask nano-typeless
          </code>
        </div>

        {/* GitHub */}
        <div
          style={{
            opacity: commandOpacity,
            display: "flex",
            alignItems: "center",
            gap: 10,
          }}
        >
          <span style={{ fontSize: 20 }}>⭐</span>
          <span
            style={{
              fontSize: 16,
              color: colors.textMuted,
            }}
          >
            github.com/ZhaoChaoqun/typeless
          </span>
        </div>
      </div>
    </AbsoluteFill>
  );
};

// 横版主视频组件
export const TypelessPromoV2: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {/* 背景音乐 */}
      <Audio src={staticFile("mehul-choudhary-effortless.mp3")} volume={0.25} />

      {/* 旁白：场景1 - Nano Typeless，按下即说 */}
      <Sequence from={20}>
        <Audio src={staticFile("vo_v2_1.mp3")} volume={1} />
      </Sequence>

      {/* 旁白：场景2 - 帮我配置 GitHub Actions */}
      <Sequence from={120}>
        <Audio src={staticFile("vo_v2_2.mp3")} volume={1} />
      </Sequence>

      {/* 旁白：场景3 - 纯本地运行，极速响应，支持中英文混合 */}
      <Sequence from={260}>
        <Audio src={staticFile("vo_v2_3.mp3")} volume={1} />
      </Sequence>

      {/* 旁白：场景4 - 别让打字限制你的代码灵感，立即下载 */}
      <Sequence from={440}>
        <Audio src={staticFile("vo_v2_4.mp3")} volume={1} />
      </Sequence>

      {/* 场景1：转场 0-90帧 (0-3秒) */}
      <Sequence from={0} durationInFrames={90}>
        <Scene1_Transition />
      </Sequence>

      {/* 场景2：核心演示 90-240帧 (3-8秒) */}
      <Sequence from={90} durationInFrames={150}>
        <Scene2_Demo />
      </Sequence>

      {/* 场景3：硬核背书 240-420帧 (8-14秒) - 3个卖点各2秒 */}
      <Sequence from={240} durationInFrames={180}>
        <Scene3_Features />
      </Sequence>

      {/* 场景4：CTA 420-555帧 (14-18.5秒) */}
      <Sequence from={420} durationInFrames={135}>
        <Scene4_CTA />
      </Sequence>
    </AbsoluteFill>
  );
};
