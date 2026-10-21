import Foundation

/// The VLM observation call (spec section 4.1): prompt text, the GBNF grammar
/// that constrains decoding to exactly this JSON shape, and the retry prompt.
public enum ObservationPrompt {
    public static let system = "You are a careful visual describer for a party game."

    public static let user = """
    Look at the person in the photo.
    Return ONLY a JSON object with exactly these keys:
    {
      "hair_color": one of ["black","brown","blonde","red","gray","white","dyed-other","hidden","unknown"],
      "eye_color": one of ["brown","blue","green","hazel","gray","unknown"],
      "shirt_color": short color name,
      "age_band": one of ["child","teen","20s","30s","40s","50s","60+","unknown"],
      "expression": one of ["smiling","serious","surprised","sleepy","silly-face","unknown"],
      "accessories": array of up to 3 from ["glasses","sunglasses","hat","hood","headphones","earrings","necklace","scarf","mask","none"],
      "background_hint": up to 4 words describing the setting
    }
    Use "unknown" whenever you are not sure. Do not describe skin, body shape, weight, ethnicity,
    attractiveness, health, or disabilities. Do not guess names or identities.
    """

    /// Second attempt after unparseable output.
    public static let retryUser = user + "\nReturn only valid JSON."

    /// Upper bound on generated tokens (spec section 6: ~120).
    public static let maxTokens = 120

    /// GBNF grammar (llama.cpp) matching the schema above, keys in order.
    /// Free-text fields are limited to letters, spaces and a few separators,
    /// so the model can't smuggle long prose into them.
    public static let grammar: String = {
        func choice(_ values: [String]) -> String {
            values.map { "\"\\\"\($0)\\\"\"" }.joined(separator: " | ")
        }
        let hair = HairColor.allCases.map(\.rawValue)
        let eye = EyeColor.allCases.map(\.rawValue)
        let age = AgeBand.allCases.map(\.rawValue)
        let expression = FaceExpression.allCases.map(\.rawValue)
        let accessory = Accessory.allCases.map(\.rawValue)
        return """
        root ::= "{" ws "\\"hair_color\\":" ws hair "," ws "\\"eye_color\\":" ws eye "," ws "\\"shirt_color\\":" ws short "," ws "\\"age_band\\":" ws age "," ws "\\"expression\\":" ws expr "," ws "\\"accessories\\":" ws accs "," ws "\\"background_hint\\":" ws short ws "}"
        hair ::= \(choice(hair))
        eye ::= \(choice(eye))
        age ::= \(choice(age))
        expr ::= \(choice(expression))
        acc ::= \(choice(accessory))
        accs ::= "[" ws "]" | "[" ws acc ( ws "," ws acc ){0,2} ws "]"
        short ::= "\\"" [a-zA-Z] [a-zA-Z ,'/-]{0,39} "\\""
        ws ::= [ \\t\\n]{0,3}
        """
    }()
}
