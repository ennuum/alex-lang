# Module string natif : mêmes résultats que le module string de la VM.
from core use len
use string
from string use split, join, upper
s := "  Bonjour le Monde, été  "
print(string.upper(s), string.lower(s))
print(string.capitalize("hELLO wORLD"), string.title("hello  wide\tworld"))
print("[" + string.trim(s) + "]", "[" + string.strip("\n x \r") + "]")
print(string.count("abababa", "aba"), string.repeat("ab", 3), string.repeat("x", 0) == "")
print(string.find("héllo", "llo"), string.find("abc", "z"), string.find("abc", ""))
print(string.substring("héllo", 1, 4))
parts := split("a,b,,c", ",")
print(parts, len(parts))
print(join("-", parts), join("", []))
print(string.replace("aaa", "a", "bb"), string.replace("été", "é", "e"))
print(string.starts_with("prefix", "pre"), string.ends_with("prefix", "fix"), string.contains("abc", "bd"), string.contains("abc", ""))
print(string.chr(233), string.ord('é'), string.chr(128512))
print(string.slice("abcdef", 1, 4), string.slice("abcdef", null, null, -1), string.slice("héllo", -3), string.slice("abcdef", 0, 6, 2))
print(upper("ok"))
