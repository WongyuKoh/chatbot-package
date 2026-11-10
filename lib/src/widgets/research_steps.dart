import 'package:flutter/material.dart';

import '../config/gist_chatbot_config.dart';
import '../state/chat_message.dart';
import 'loading_shimmer.dart';

const _researchKind = 'research';

/// 서버가 research 단계를 보내지 않았을 때의 기본 문구 (웹 위젯과 동일)
const _researchingLabel = '자료를 더 찾아보고 있어요';
const _writingLabel = '답변을 정리하고 있어요';

/// 실패해도 답변은 계속 오므로 오류색 대신 경고색
const _warningColor = Color(0xFFD97706);

/// 에이전트 조사 단계 표시 (웹 위젯의 AgentSteps와 동일)
///
/// - [live]: 답변 본문이 오기 전. 진행 문구와 도구 단계를 펼쳐서 실시간으로 보여 준다.
/// - 그 뒤: 한 줄 요약으로 접고, 탭하면 도구 단계를 펼친다.
///
/// kind가 research인 단계는 조사 전체를 나타내고, 나머지는 개별 도구 호출이다.
class ResearchSteps extends StatefulWidget {
  const ResearchSteps({
    super.key,
    required this.steps,
    required this.colors,
    this.live = false,
  });

  final List<ResearchStep> steps;
  final GistChatbotColors colors;
  final bool live;

  @override
  State<ResearchSteps> createState() => _ResearchStepsState();
}

class _ResearchStepsState extends State<ResearchSteps> {
  bool _expanded = false;

  ResearchStep? get _research {
    for (final step in widget.steps) {
      if (step.kind == _researchKind) return step;
    }
    return null;
  }

  ResearchStepStatus get _summaryStatus {
    final research = _research;
    if (research != null) return research.status;
    final steps = widget.steps;
    if (steps.any((s) => s.status == ResearchStepStatus.running)) {
      return ResearchStepStatus.running;
    }
    if (steps.any((s) => s.status == ResearchStepStatus.stopped)) {
      return ResearchStepStatus.stopped;
    }
    if (steps.every((s) => s.status == ResearchStepStatus.failed)) {
      return ResearchStepStatus.failed;
    }
    return ResearchStepStatus.done;
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final research = _research;
    final toolSteps = [
      for (final step in widget.steps)
        if (step.kind != _researchKind) step,
    ];

    if (widget.live) {
      // research가 닫혔는데 아직 답변이 안 왔으면 답변 생성 대기 중
      final header =
          research == null || research.status == ResearchStepStatus.running
          ? (research?.label ?? _researchingLabel)
          : _writingLabel;
      return Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            LoadingIndicatorRow(message: header, color: colors.textSecondary),
            if (toolSteps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _ToolStepList(steps: toolSteps, colors: colors),
              ),
          ],
        ),
      );
    }

    final status = _summaryStatus;
    // research가 failed·stopped면 서버 label이 진행 중 문구 그대로라 요약 문구를 따로 둔다
    final summaryText = switch (status) {
      ResearchStepStatus.running => research?.label ?? _researchingLabel,
      ResearchStepStatus.stopped => '자료 찾기를 중단했어요',
      ResearchStepStatus.failed => '자료를 더 찾지 못했어요',
      ResearchStepStatus.done => research?.label ?? '자료를 찾아봤어요',
    };
    final expandable = toolSteps.isNotEmpty;

    final summary = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepStatusIcon(
          status: status,
          resultCount: research?.resultCount,
          colors: colors,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            summaryText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ),
        if (expandable) ...[
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (expandable)
            Semantics(
              button: true,
              expanded: _expanded,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  // 한 줄 요약이라 터치 영역을 위아래로 넓힌다
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: summary,
                ),
              ),
            )
          else
            summary,
          if (expandable && _expanded)
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 4),
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: colors.border, width: 2),
                ),
              ),
              child: _ToolStepList(steps: toolSteps, colors: colors),
            ),
        ],
      ),
    );
  }
}

class _ToolStepList extends StatelessWidget {
  const _ToolStepList({required this.steps, required this.colors});

  final List<ResearchStep> steps;
  final GistChatbotColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, step) in steps.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1.5),
                  child: _StepStatusIcon(
                    status: step.status,
                    resultCount: step.resultCount,
                    colors: colors,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        step.label,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      if (step.thought != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _formatThought(step.thought!),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 모델이 쓴 문장이라 끝 마침표가 있거나 없을 수 있어 통일
String _formatThought(String thought) =>
    thought.trim().replaceFirst(RegExp(r'[.。]+$'), '');

class _StepStatusIcon extends StatelessWidget {
  const _StepStatusIcon({
    required this.status,
    required this.colors,
    this.resultCount,
  });

  final ResearchStepStatus status;
  final GistChatbotColors colors;
  final int? resultCount;

  static const double _size = 14;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ResearchStepStatus.running:
        return Semantics(
          label: '진행 중',
          child: SizedBox(
            width: _size,
            height: _size,
            child: Padding(
              padding: const EdgeInsets.all(1.5),
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colors.textSecondary,
                // 애니메이션 줄이기가 켜져 있으면 멈춘 고리로 표시
                value: MediaQuery.disableAnimationsOf(context) ? 0.75 : null,
              ),
            ),
          ),
        );
      case ResearchStepStatus.done:
        return Icon(
          Icons.check_circle_outline_rounded,
          size: _size,
          // 결과 없이 끝난 단계는 흐리게
          color: resultCount == 0 ? colors.textSecondary : colors.primary,
          semanticLabel: '완료',
        );
      case ResearchStepStatus.failed:
        return const Icon(
          Icons.warning_amber_rounded,
          size: _size,
          color: _warningColor,
          semanticLabel: '실패',
        );
      case ResearchStepStatus.stopped:
        return Icon(
          Icons.remove_circle_outline_rounded,
          size: _size,
          color: colors.textSecondary,
          semanticLabel: '중단됨',
        );
    }
  }
}
