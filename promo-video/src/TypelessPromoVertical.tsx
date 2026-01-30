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

// 颜色配置 - iPhone 发布会风格
const colors = {
  background: "#000000",
  text: "#ffffff",
  textMuted: "rgba(255, 255, 255, 0.6)",
  accent: "#0071e3",
  gradientStart: "#1a1a1a",
  gradientEnd: "#000000",
};

// 竖版烟雾效果 - 适配 9:16 比例
const SmokeEffectVertical: React.FC<{ intensity?: number }> = ({ intensity = 1 }) => {
  const frame = useCurrentFrame();

  // 烟雾层配置 - 适配竖屏
  const smokeLayers = [
    { id: 0, x: -100, y: 500, width: 700, height: 900, rotation: 0, speed: 0.3, scaleBase: 1.2, color: "rgba(90, 50, 150, 0.4)" },
    { id: 1, x: 800, y: 800, width: 650, height: 850, rotation: 10, speed: 0.25, scaleBase: 1.1, color: "rgba(120, 80, 180, 0.35)" },
    { id: 2, x: 200, y: 200, width: 500, height: 700, rotation: -15, speed: 0.4, scaleBase: 1.0, color: "rgba(140, 100, 200, 0.3)" },
    { id: 3, x: 600, y: 1200, width: 550, height: 750, rotation: 5, speed: 0.35, scaleBase: 1.05, color: "rgba(100, 60, 160, 0.35)" },
    { id: 4, x: 100, y: 1000, width: 400, height: 600, rotation: -5, speed: 0.5, scaleBase: 0.9, color: "rgba(160, 120, 220, 0.25)" },
    { id: 5, x: 700, y: 300, width: 450, height: 650, rotation: 12, speed: 0.45, scaleBase: 0.95, color: "rgba(130, 90, 190, 0.28)" },
  ];

  const smokeBlobs = [
    { id: 0, baseX: 200, baseY: 400, size: 250, phaseX: 0, phaseY: 0.5, speedX: 0.015, speedY: 0.012, color: "rgba(150, 100, 210, 0.5)" },
    { id: 1, baseX: 800, baseY: 800, size: 300, phaseX: 1, phaseY: 1.5, speedX: 0.012, speedY: 0.018, color: "rgba(120, 80, 180, 0.45)" },
    { id: 2, baseX: 500, baseY: 1400, size: 220, phaseX: 2, phaseY: 0, speedX: 0.018, speedY: 0.01, color: "rgba(170, 130, 230, 0.4)" },
    { id: 3, baseX: 400, baseY: 250, size: 280, phaseX: 0.5, phaseY: 2, speedX: 0.01, speedY: 0.015, color: "rgba(100, 70, 160, 0.5)" },
    { id: 4, baseX: 700, baseY: 1800, size: 240, phaseX: 1.5, phaseY: 1, speedX: 0.014, speedY: 0.016, color: "rgba(140, 100, 200, 0.42)" },
  ];

  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        overflow: "hidden",
        opacity: intensity,
        background: "linear-gradient(180deg, #0a0512 0%, #000000 50%, #0a0512 100%)",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `
            radial-gradient(ellipse 80% 60% at 30% 20%, rgba(80, 40, 140, 0.3) 0%, transparent 60%),
            radial-gradient(ellipse 70% 50% at 70% 80%, rgba(100, 60, 160, 0.25) 0%, transparent 55%)
          `,
        }}
      />

      {smokeLayers.map((layer) => {
        const time = frame * layer.speed;
        const offsetX = Math.sin(time * 0.02 + layer.id) * 40;
        const offsetY = Math.cos(time * 0.015 + layer.id * 0.5) * 50;
        const scale = layer.scaleBase + Math.sin(time * 0.01 + layer.id) * 0.1;
        const rotation = layer.rotation + Math.sin(time * 0.008 + layer.id) * 5;
        const opacity = 0.7 + Math.sin(time * 0.012 + layer.id * 0.7) * 0.3;

        return (
          <div
            key={`layer-${layer.id}`}
            style={{
              position: "absolute",
              left: layer.x + offsetX,
              top: layer.y + offsetY,
              width: layer.width,
              height: layer.height,
              borderRadius: "50%",
              background: `radial-gradient(ellipse at center, ${layer.color} 0%, transparent 70%)`,
              transform: `scale(${scale}) rotate(${rotation}deg)`,
              filter: "blur(80px)",
              opacity,
              mixBlendMode: "screen",
            }}
          />
        );
      })}

      {smokeBlobs.map((blob) => {
        const x = blob.baseX + Math.sin(frame * blob.speedX + blob.phaseX) * 80;
        const y = blob.baseY + Math.cos(frame * blob.speedY + blob.phaseY) * 100;
        const scale = 1 + Math.sin(frame * 0.02 + blob.id) * 0.15;
        const opacity = 0.6 + Math.sin(frame * 0.015 + blob.id * 0.5) * 0.4;

        return (
          <div
            key={`blob-${blob.id}`}
            style={{
              position: "absolute",
              left: x,
              top: y,
              width: blob.size,
              height: blob.size,
              borderRadius: "50%",
              background: `radial-gradient(circle at 40% 40%, ${blob.color}, transparent 70%)`,
              transform: `scale(${scale})`,
              filter: "blur(50px)",
              opacity,
              mixBlendMode: "screen",
            }}
          />
        );
      })}

      <div
        style={{
          position: "absolute",
          left: "50%",
          top: "40%",
          width: 600,
          height: 800,
          marginLeft: -300,
          marginTop: -400,
          background: `
            radial-gradient(ellipse 100% 80% at 50% 50%,
              rgba(180, 150, 255, 0.15) 0%,
              rgba(140, 100, 220, 0.08) 30%,
              transparent 60%)
          `,
          filter: "blur(40px)",
          opacity: 0.5 + Math.sin(frame * 0.015) * 0.2,
        }}
      />

      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `radial-gradient(ellipse 70% 60% at 50% 50%, transparent 30%, rgba(0,0,0,0.6) 100%)`,
          pointerEvents: "none",
        }}
      />

      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `
            linear-gradient(to bottom, rgba(0,0,0,0.8) 0%, transparent 10%, transparent 90%, rgba(0,0,0,0.8) 100%)
          `,
          pointerEvents: "none",
        }}
      />
    </div>
  );
};

// HUD 组件 - 竖版尺寸
const HUDVertical: React.FC<{ state: "recording" | "processing"; frame: number }> = ({
  state,
  frame,
}) => {
  const dots = 5;

  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 6,
        padding: "16px 28px",
        background: "rgba(0, 0, 0, 0.85)",
        borderRadius: 30,
        boxShadow: "0 4px 20px rgba(0, 0, 0, 0.5)",
      }}
    >
      {state === "recording" ? (
        [...Array(dots)].map((_, i) => {
          const phase = frame * 0.3 + i * 0.5;
          const offset = Math.sin(phase) * 8;
          return (
            <div
              key={i}
              style={{
                width: 12,
                height: 12,
                borderRadius: "50%",
                background: "#ffffff",
                transform: `translateY(${offset}px)`,
              }}
            />
          );
        })
      ) : (
        <div
          style={{
            width: 28,
            height: 28,
            border: "3px solid rgba(255,255,255,0.3)",
            borderTopColor: "#fff",
            borderRadius: "50%",
            transform: `rotate(${frame * 10}deg)`,
          }}
        />
      )}
    </div>
  );
};

// 竖版输入区域
const InputAreaVertical: React.FC<{
  text: string;
  showCursor?: boolean;
}> = ({ text, showCursor = true }) => {
  const frame = useCurrentFrame();
  const cursorVisible = showCursor && Math.floor(frame / 15) % 2 === 0;

  return (
    <div
      style={{
        background: "rgba(255, 255, 255, 0.05)",
        borderRadius: 24,
        padding: "40px 48px",
        width: 800,
        minHeight: 150,
        border: "1px solid rgba(255, 255, 255, 0.1)",
        backdropFilter: "blur(20px)",
      }}
    >
      <p
        style={{
          fontSize: 42,
          fontWeight: 400,
          color: colors.text,
          fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif",
          lineHeight: 1.5,
          margin: 0,
          textAlign: "center",
        }}
      >
        {text}
        {cursorVisible && (
          <span
            style={{
              display: "inline-block",
              width: 4,
              height: 48,
              background: colors.accent,
              marginLeft: 4,
              verticalAlign: "middle",
            }}
          />
        )}
      </p>
    </div>
  );
};

// 竖版场景1：开场
const Scene1_IntroVertical: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const logoScale = spring({
    frame,
    fps,
    config: { damping: 12 },
  });

  const logoOpacity = interpolate(frame, [0, 20], [0, 1], {
    extrapolateRight: "clamp",
  });

  const titleOpacity = interpolate(frame, [25, 45], [0, 1], {
    extrapolateRight: "clamp",
  });

  const titleY = interpolate(frame, [25, 45], [40, 0], {
    extrapolateRight: "clamp",
  });

  const subtitleOpacity = interpolate(frame, [50, 70], [0, 1], {
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        background: colors.background,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <SmokeEffectVertical intensity={0.9} />

      <Img
        src={staticFile("icon_512x512.png")}
        style={{
          transform: `scale(${logoScale})`,
          opacity: logoOpacity,
          marginBottom: 48,
          width: 180,
          height: 180,
          borderRadius: 42,
          boxShadow: "0 30px 80px rgba(102, 126, 234, 0.4)",
        }}
      />

      <h1
        style={{
          fontSize: 120,
          fontWeight: 700,
          color: colors.text,
          opacity: titleOpacity,
          transform: `translateY(${titleY}px)`,
          fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif",
          letterSpacing: "-3px",
          margin: 0,
          textAlign: "center",
        }}
      >
        nano typeless
      </h1>

      <p
        style={{
          fontSize: 48,
          fontWeight: 500,
          color: colors.textMuted,
          opacity: subtitleOpacity,
          marginTop: 30,
          fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif",
          letterSpacing: "12px",
        }}
      >
        PRESS. SPEAK.
      </p>
    </AbsoluteFill>
  );
};

// 竖版场景2：录音演示
const Scene2_RecordingVertical: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const hudOpacity = interpolate(frame, [0, 15], [0, 1], {
    extrapolateRight: "clamp",
  });

  const hudScale = spring({
    frame,
    fps,
    config: { damping: 15 },
  });

  const fnKeyOpacity = interpolate(frame, [20, 35], [0, 1], {
    extrapolateRight: "clamp",
  });

  const fnKeyPressed = frame > 40;

  return (
    <AbsoluteFill
      style={{
        background: colors.background,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <SmokeEffectVertical intensity={0.8} />

      <div
        style={{
          position: "absolute",
          top: 400,
          opacity: hudOpacity,
          transform: `scale(${hudScale * 1.3})`,
        }}
      >
        <HUDVertical state="recording" frame={frame} />
      </div>

      <div
        style={{
          position: "absolute",
          bottom: 600,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 30,
          opacity: fnKeyOpacity,
        }}
      >
        <div
          style={{
            width: 120,
            height: 120,
            borderRadius: 24,
            background: fnKeyPressed
              ? "linear-gradient(135deg, #667eea 0%, #764ba2 100%)"
              : "rgba(255, 255, 255, 0.1)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 42,
            fontWeight: 600,
            color: "#fff",
            boxShadow: fnKeyPressed
              ? "0 0 60px rgba(102, 126, 234, 0.6)"
              : "none",
            border: fnKeyPressed ? "none" : "1px solid rgba(255,255,255,0.2)",
          }}
        >
          Fn
        </div>
        <span
          style={{
            fontSize: 36,
            color: colors.textMuted,
            fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
          }}
        >
          {fnKeyPressed ? "正在聆听..." : "长按开始"}
        </span>
      </div>

      {fnKeyPressed && (
        <div
          style={{
            position: "absolute",
            top: 700,
            display: "flex",
            alignItems: "center",
            gap: 8,
          }}
        >
          {[...Array(15)].map((_, i) => {
            const height = interpolate(
              Math.sin((frame + i * 8) * 0.25),
              [-1, 1],
              [20, 80]
            );
            const opacity = interpolate(
              Math.abs(i - 7),
              [0, 7],
              [1, 0.3]
            );
            return (
              <div
                key={i}
                style={{
                  width: 6,
                  height,
                  background: `rgba(102, 126, 234, ${opacity})`,
                  borderRadius: 3,
                }}
              />
            );
          })}
        </div>
      )}
    </AbsoluteFill>
  );
};

// 竖版场景3：文字快速输出
const Scene3_FastOutputVertical: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const fullText = "语音转文字，快如闪电";

  const typedLength = Math.floor(
    interpolate(frame, [10, 40], [0, fullText.length], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    })
  );
  const displayText = fullText.slice(0, typedLength);

  const inputOpacity = interpolate(frame, [0, 15], [0, 1], {
    extrapolateRight: "clamp",
  });

  const speedBadgeOpacity = interpolate(frame, [50, 65], [0, 1], {
    extrapolateRight: "clamp",
  });

  const speedBadgeScale = spring({
    frame: frame - 50,
    fps,
    config: { damping: 10 },
  });

  const hudState = frame < 35 ? "recording" : "processing";
  const hudOpacity = interpolate(frame, [60, 75], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        background: colors.background,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <SmokeEffectVertical intensity={0.8} />

      <div
        style={{
          position: "absolute",
          top: 350,
          opacity: hudOpacity,
          transform: "scale(1.3)",
        }}
      >
        <HUDVertical state={hudState} frame={frame} />
      </div>

      <div style={{ opacity: inputOpacity }}>
        <InputAreaVertical text={displayText} showCursor={frame < 70} />
      </div>

      <div
        style={{
          position: "absolute",
          bottom: 500,
          opacity: speedBadgeOpacity,
          transform: `scale(${Math.max(0, speedBadgeScale)})`,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 20,
        }}
      >
        <span style={{ fontSize: 72 }}>⚡</span>
        <span
          style={{
            fontSize: 36,
            fontWeight: 600,
            color: colors.text,
            fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
          }}
        >
          本地处理，极速响应
        </span>
      </div>
    </AbsoluteFill>
  );
};

// 竖版场景4：特性展示 - 竖排布局
const Scene4_FeaturesVertical: React.FC = () => {
  const frame = useCurrentFrame();

  const features = [
    { icon: "lock.png", title: "100% 本地", desc: "隐私安全" },
    { icon: "high-voltage.png", title: "极速识别", desc: "毫秒响应" },
    { icon: "globe-with-meridians.png", title: "中英混合", desc: "智能切换" },
  ];

  return (
    <AbsoluteFill
      style={{
        background: colors.background,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <SmokeEffectVertical intensity={0.7} />

      <div style={{ display: "flex", flexDirection: "column", gap: 80 }}>
        {features.map((feature, index) => {
          const delay = index * 15;
          const opacity = interpolate(frame - delay, [0, 20], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          });
          const x = interpolate(frame - delay, [0, 20], [60, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          });

          return (
            <div
              key={index}
              style={{
                display: "flex",
                flexDirection: "row",
                alignItems: "center",
                gap: 40,
                opacity,
                transform: `translateX(${x}px)`,
              }}
            >
              <div
                style={{
                  width: 140,
                  height: 140,
                  borderRadius: 35,
                  background: "rgba(255, 255, 255, 0.08)",
                  border: "1px solid rgba(255, 255, 255, 0.15)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  flexShrink: 0,
                }}
              >
                <Img
                  src={staticFile(feature.icon)}
                  style={{
                    width: 85,
                    height: 85,
                  }}
                />
              </div>
              <div>
                <h3
                  style={{
                    fontSize: 42,
                    fontWeight: 600,
                    color: colors.text,
                    margin: 0,
                    marginBottom: 12,
                    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
                  }}
                >
                  {feature.title}
                </h3>
                <p
                  style={{
                    fontSize: 28,
                    color: colors.textMuted,
                    margin: 0,
                    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
                  }}
                >
                  {feature.desc}
                </p>
              </div>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// 竖版场景5：结尾 CTA
const Scene5_CTAVertical: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const titleOpacity = interpolate(frame, [0, 20], [0, 1], {
    extrapolateRight: "clamp",
  });

  const titleScale = spring({
    frame,
    fps,
    config: { damping: 12 },
  });

  const commandOpacity = interpolate(frame, [30, 50], [0, 1], {
    extrapolateRight: "clamp",
  });

  const commandY = interpolate(frame, [30, 50], [30, 0], {
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        background: colors.background,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <SmokeEffectVertical intensity={0.9} />

      <Img
        src={staticFile("icon_512x512.png")}
        style={{
          width: 120,
          height: 120,
          borderRadius: 30,
          marginBottom: 40,
          opacity: titleOpacity,
          transform: `scale(${titleScale})`,
          boxShadow: "0 15px 50px rgba(102, 126, 234, 0.3)",
        }}
      />

      <h1
        style={{
          fontSize: 90,
          fontWeight: 700,
          color: colors.text,
          opacity: titleOpacity,
          transform: `scale(${titleScale})`,
          fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif",
          letterSpacing: "-2px",
          margin: 0,
          marginBottom: 60,
          textAlign: "center",
        }}
      >
        nano typeless
      </h1>

      <div
        style={{
          opacity: commandOpacity,
          transform: `translateY(${commandY}px)`,
          background: "rgba(255, 255, 255, 0.05)",
          borderRadius: 16,
          padding: "28px 48px",
          border: "1px solid rgba(255, 255, 255, 0.1)",
          display: "flex",
          flexDirection: "column",
          gap: 12,
        }}
      >
        <code
          style={{
            fontSize: 28,
            color: "#10b981",
            fontFamily: "SF Mono, Menlo, monospace",
          }}
        >
          brew tap ZhaoChaoqun/typeless
        </code>
        <code
          style={{
            fontSize: 28,
            color: "#10b981",
            fontFamily: "SF Mono, Menlo, monospace",
          }}
        >
          brew install --cask nano-typeless
        </code>
      </div>

      <p
        style={{
          fontSize: 24,
          color: colors.textMuted,
          marginTop: 50,
          opacity: commandOpacity,
          fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
        }}
      >
        github.com/ZhaoChaoqun/typeless
      </p>
    </AbsoluteFill>
  );
};

// 竖版主视频组件
export const TypelessPromoVertical: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: colors.background }}>
      {/* 背景音乐 */}
      <Audio
        src={staticFile("mehul-choudhary-effortless.mp3")}
        volume={0.25}
        startFrom={0}
      />

      {/* 旁白 */}
      <Sequence from={30}>
        <Audio src={staticFile("vo1.m4a")} volume={1} />
      </Sequence>

      <Sequence from={100}>
        <Audio src={staticFile("vo2.m4a")} volume={1} />
      </Sequence>

      <Sequence from={190}>
        <Audio src={staticFile("vo3.m4a")} volume={1} />
      </Sequence>

      <Sequence from={290}>
        <Audio src={staticFile("vo4.m4a")} volume={1} />
      </Sequence>

      <Sequence from={420}>
        <Audio src={staticFile("vo5.m4a")} volume={1} />
      </Sequence>

      {/* 场景1：开场 0-90帧 (3秒) */}
      <Sequence from={0} durationInFrames={90}>
        <Scene1_IntroVertical />
      </Sequence>

      {/* 场景2：录音演示 90-180帧 (3秒) */}
      <Sequence from={90} durationInFrames={90}>
        <Scene2_RecordingVertical />
      </Sequence>

      {/* 场景3：快速输出 180-270帧 (3秒) */}
      <Sequence from={180} durationInFrames={90}>
        <Scene3_FastOutputVertical />
      </Sequence>

      {/* 场景4：特性展示 270-390帧 (4秒) */}
      <Sequence from={270} durationInFrames={120}>
        <Scene4_FeaturesVertical />
      </Sequence>

      {/* 场景5：结尾 CTA 390-540帧 (5秒) */}
      <Sequence from={390} durationInFrames={150}>
        <Scene5_CTAVertical />
      </Sequence>
    </AbsoluteFill>
  );
};
