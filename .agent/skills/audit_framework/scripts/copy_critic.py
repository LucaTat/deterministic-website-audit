"""
copy_critic.py - Content Quality Analysis.

Usage:
    report = analyze_copy(text_content)
"""

import re

def count_syllables(word):
    word = word.lower()
    count = 0
    vowels = "aeiouy"
    if word[0] in vowels:
        count += 1
    for index in range(1, len(word)):
        if word[index] in vowels and word[index - 1] not in vowels:
            count += 1
    if word.endswith("e"):
        count -= 1
    if count == 0:
        count += 1
    return count

def analyze_copy(text: str) -> dict:
    """
    Returns metrics on readability and tone.
    """
    # Normalize
    clean = re.sub(r'\s+', ' ', text).strip()
    if not clean:
        return {"error": "Empty text"}

    sentences = re.split(r'[.!?]+', clean)
    sentences = [s for s in sentences if len(s.strip()) > 1]
    words = re.findall(r'\b\w+\b', clean)
    
    total_sentences = len(sentences)
    total_words = len(words)
    total_syllables = sum(count_syllables(w) for w in words)
    
    if total_sentences == 0 or total_words == 0:
        return {"error": "Insufficient content"}
        
    # Flesch Reading Ease
    # 206.835 - 1.015(total words / total sentences) - 84.6(total syllables / total words)
    avg_sentence_len = total_words / total_sentences
    avg_syllables = total_syllables / total_words
    
    flesch_score = 206.835 - (1.015 * avg_sentence_len) - (84.6 * avg_syllables)
    
    difficulty = "Unknown"
    if flesch_score > 90: difficulty = "Very Easy (5th grade)"
    elif flesch_score > 80: difficulty = "Easy (6th grade)"
    elif flesch_score > 70: difficulty = "Fairly Easy (7th grade)"
    elif flesch_score > 60: difficulty = "Standard (8th-9th grade)"
    elif flesch_score > 50: difficulty = "Fairly Difficult (High School)"
    elif flesch_score > 30: difficulty = "Difficult (College)"
    else: difficulty = "Very Difficult (Academic)"
    
    # You vs We Ratio
    you_count = len(re.findall(r'\b(you|your|yours)\b', clean, re.I))
    we_count = len(re.findall(r'\b(we|our|us)\b', clean, re.I))
    
    tone = "Neutral"
    if you_count > we_count * 1.5:
        tone = "Customer-Centric (Good)"
    elif we_count > you_count * 1.5:
        tone = "Company-Centric (Bad)"
        
    return {
        "word_count": total_words,
        "flesch_score": round(flesch_score, 1),
        "difficulty_label": difficulty,
        "you_we_ratio": f"{you_count}:{we_count}",
        "tone_label": tone
    }
