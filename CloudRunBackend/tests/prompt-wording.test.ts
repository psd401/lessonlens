/**
 * Pins the coaching (not evaluation) wording of the analysis and chat prompts,
 * so a future edit that brings evaluation language back fails here.
 */
import { describe, expect, test } from 'bun:test';
import {
  buildAnalysisPrompt,
  buildVideoAnalysisPrompt,
  buildChatPrompt,
  type TechniqueDefinition,
} from '../../shared/prompts';

const technique: TechniqueDefinition = {
  id: 'wait-time',
  name: 'Wait Time',
  description: 'Pause after asking a question.',
  lookFors: ['Teacher pauses 3+ seconds'],
  exemplarPhrases: ['Take a moment to think.'],
};

const prompts = {
  text: buildAnalysisPrompt({ transcript: 'Hello class.', techniques: [technique], includeRatings: true }),
  video: buildVideoAnalysisPrompt({ techniques: [technique], includeRatings: true }),
  chat: buildChatPrompt({
    transcript: 'Hello class.',
    analysisSummary: 'Summary',
    techniqueEvaluationsSummary: 'Wait Time: observed',
    messages: [],
    techniqueNames: ['Wait Time'],
  }).systemPrompt,
};

describe('prompt wording stays coaching, not evaluation', () => {
  for (const [name, prompt] of Object.entries(prompts)) {
    test(`${name} prompt does not ask the model to evaluate the teacher`, () => {
      expect(prompt).not.toMatch(/evaluate the teacher/i);
      expect(prompt).not.toContain('Techniques to Evaluate');
      expect(prompt).not.toContain('techniques evaluated');
      expect(prompt).not.toContain("session's effectiveness");
    });
  }

  test('analysis prompts describe technique use', () => {
    expect(prompts.text).toContain('describe how the teacher used specific teaching techniques');
    expect(prompts.video).toContain('describe how the teacher used specific teaching techniques');
    expect(prompts.text).toContain('## Techniques to Look For');
    expect(prompts.video).toContain('## Techniques to Look For');
  });

  test('chat prompt names the analyzed techniques', () => {
    expect(prompts.chat).toContain('The techniques analyzed in this session were: Wait Time.');
  });
});

describe('rating scale describes the technique, not the teacher', () => {
  const textPrompt = prompts.text;

  test('uses the agreed labels in order', () => {
    const labels = [...textPrompt.matchAll(/^(\d) - (\w+):/gm)].map((m) => `${m[1]} ${m[2]}`);
    expect(labels).toEqual(['1 Emerging', '2 Developing', '3 Established', '4 Refining', '5 Extending']);
  });

  test('avoids evaluation-system and superlative labels', () => {
    for (const word of ['Unsatisfactory', 'Basic', 'Proficient', 'Distinguished', 'Accomplished', 'Exemplary']) {
      expect(textPrompt).not.toContain(word);
    }
  });

  test('rates how fully a technique was carried out, not how often', () => {
    expect(textPrompt).toContain('not how often it came up');
    expect(textPrompt).toContain('including when the lesson gave no occasion for it');
  });
});

