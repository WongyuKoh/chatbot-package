import 'package:flutter/material.dart';

import '../config/gist_chatbot_config.dart';
import 'pressable.dart';

/// 자주 묻는 질문 (웹 위젯의 frequentQuestions.ts와 동일)
class FrequentQuestion {
  const FrequentQuestion({
    required this.icon,
    required this.label,
    this.question,
  });

  /// 아이콘 (이모지)
  final String icon;

  /// 카드에 표시될 짧은 라벨
  final String label;

  /// 실제 전송될 질문 내용 (생략 시 label이 사용됩니다)
  final String? question;
}

const List<FrequentQuestion> kFrequentQuestions = [
  FrequentQuestion(icon: '📅', label: '학사 일정', question: '이번 학기 학사 일정을 알려주세요.'),
  FrequentQuestion(icon: '📝', label: '수강신청 방법', question: '수강신청은 어떻게 하나요?'),
  FrequentQuestion(
    icon: '💰',
    label: '장학금 안내',
    question: '장학금 종류와 신청 방법을 알려주세요.',
  ),
  FrequentQuestion(
    icon: '🪪',
    label: '모바일 출입카드 발급',
    question: '모바일 출입카드는 어디서 어떻게 발급받나요?',
  ),
  FrequentQuestion(
    icon: '📶',
    label: 'Wi-Fi 연결',
    question: '학교 Wi-Fi는 어떻게 연결하나요?',
  ),
  FrequentQuestion(
    icon: '🗺️',
    label: '캠퍼스 맵',
    question: '캠퍼스 지도와 주요 건물 위치를 알려주세요.',
  ),
  FrequentQuestion(icon: '🎓', label: '졸업 요건 확인', question: '졸업 요건을 알려주세요.'),
  FrequentQuestion(icon: '📖', label: '전공 선언 방법', question: '전공 선언 방법을 알려주세요.'),
  FrequentQuestion(
    icon: '📞',
    label: '주요 부서 연락처',
    question: '주요 부서 연락처를 알려주세요.',
  ),
  FrequentQuestion(icon: '🏫', label: '휴학/복학 절차', question: '휴학/복학 절차를 알려주세요.'),
];

/// "이런 것들을 물어보세요" 라벨 + 2열 질문 그리드
class FrequentQuestionsSection extends StatelessWidget {
  const FrequentQuestionsSection({
    super.key,
    required this.colors,
    required this.onSelect,
  });

  final GistChatbotColors colors;
  final void Function(String text) onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '이런 것들을 물어보세요',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
                height: 1.2,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              mainAxisExtent: 42,
            ),
            itemCount: kFrequentQuestions.length,
            itemBuilder: (context, index) {
              final item = kFrequentQuestions[index];
              return _QuestionCard(
                item: item,
                colors: colors,
                onTap: () => onSelect(item.question ?? item.label),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.item,
    required this.colors,
    required this.onTap,
  });

  final FrequentQuestion item;
  final GistChatbotColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.assistantMessageBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Text(item.icon, style: const TextStyle(fontSize: 16, height: 1.2)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                  height: 1.2,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
