import Foundation

/// The VLM observation call: the spec's section 4.1 prompt, extended with
/// three kind, playful free-text fields (DECISIONS.md D-021), the GBNF
/// grammar that constrains decoding to this JSON shape, and the retry prompt.
public enum ObservationPrompt {
    public static let system = """
    You are a kind, playful visual describer for a family-friendly party game. \
    You notice fun details and describe them with warmth and gentle humour. You never insult anyone.
    """

    public static let user = """
    Look carefully at the person in the photo: what they are actually wearing and holding, their pose, \
    their expression and the background.
    Return ONLY a JSON object with exactly these keys:
    {
      "hair_color": one of ["black","brown","blonde","red","gray","white","dyed-other","hidden","unknown"],
      "eye_color": one of ["brown","blue","green","hazel","gray","unknown"],
      "shirt_color": short color name,
      "age_band": one of ["child","teen","20s","30s","40s","50s","60+","unknown"],
      "expression": one of ["smiling","serious","surprised","sleepy","silly-face","unknown"],
      "expression_read": a kind, funny take on their expression written as a playful comparison \
    ("like a ..." or "as if ..."), at most 8 words,
      "accessories": array of up to 3 from ["glasses","sunglasses","hat","hood","headphones","earrings","necklace","scarf","mask","none"],
      "fun_details": array of up to 3 kind details you can clearly see, at most 5 words each \
    (patterns, logos, accessories, things they hold, their pose, the background; not the shirt colour),
      "vibe": one silly, kind, make-believe line about who they secretly are or what they are about \
    to do, like a fairy tale or an adventure, at most 12 words,
      "background_hint": up to 4 words describing the setting
    }
    Only describe what you can clearly see. Never invent hats, glasses or other items; an empty list is fine.
    Use "unknown" whenever you are not sure.
    Be gentle, warm and playful: compliments and silly fantasy are welcome, teasing is not.
    Do not describe skin, body shape, weight, ethnicity, attractiveness, health, or disabilities. \
    Do not guess names or identities.
    In expression_read, fun_details and vibe, only talk about clothing, accessories, objects, pose, \
    expression and setting. Never mention skin or skin colour, race, ethnicity, nationality, religion, \
    body, height, age, looks, health, hair or facial hair.
    """

    /// Second attempt after unparseable output.
    public static let retryUser = user + "\nReturn only valid JSON."

    /// Upper bound on generated tokens. The spec's ~120 grew with the three
    /// playful fields (about 140 tokens in practice).
    public static let maxTokens = 200

    /// Greedy decoding: on the Mac, temperature 0.6 gave cut-off, vaguer
    /// details than greedy (DECISIONS.md D-021), and greedy keeps "same photo,
    /// same reading".
    public static let temperature: Float = 0

    /// GBNF grammar (llama.cpp) for the schema above, keys in order. Free text
    /// is limited to letters, spaces and light punctuation, and to short lengths.
    public static let grammar: String = {
        func choice(_ values: [String]) -> String {
            values.map { "\"\\\"\($0)\\\"\"" }.joined(separator: " | ")
        }
        let hair = HairColor.allCases.map(\.rawValue)
        let eye = EyeColor.allCases.map(\.rawValue)
        let age = AgeBand.allCases.map(\.rawValue)
        let expression = FaceExpression.allCases.map(\.rawValue)
        let accessory = Accessory.allCases.map(\.rawValue)
        func key(_ name: String) -> String { "\"\\\"\(name)\\\":\"" }
        return """
        root ::= "{" ws \(key("hair_color")) ws hair "," ws \(key("eye_color")) ws eye "," ws \(key("shirt_color")) ws short "," ws \(key("age_band")) ws age "," ws \(key("expression")) ws expr "," ws \(key("expression_read")) ws phrase "," ws \(key("accessories")) ws accs "," ws \(key("fun_details")) ws details "," ws \(key("vibe")) ws line "," ws \(key("background_hint")) ws short ws "}"
        hair ::= \(choice(hair))
        eye ::= \(choice(eye))
        age ::= \(choice(age))
        expr ::= \(choice(expression))
        acc ::= \(choice(accessory))
        accs ::= "[" ws "]" | "[" ws acc ( ws "," ws acc ){0,2} ws "]"
        detail ::= "\\"" [a-zA-Z] [a-zA-Z ,'-]{0,39} "\\""
        details ::= "[" ws "]" | "[" ws detail ( ws "," ws detail ){0,2} ws "]"
        short ::= "\\"" [a-zA-Z] [a-zA-Z ,'/-]{0,39} "\\""
        phrase ::= "\\"" [a-zA-Z] [a-zA-Z ,.'!-]{0,69} "\\""
        line ::= "\\"" [a-zA-Z] [a-zA-Z ,.'!-]{0,99} "\\""
        ws ::= [ \\t\\n]{0,3}
        """
    }()
}
