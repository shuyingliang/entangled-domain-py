SCRIPT_PAT = ["<", "s", "r", "i","p", "t", "/", ">"]

def issubstring(s, p):
	   i = 0
	   while i <= len(s) - len(p):
	       j = i
	       for c in p:
	           if c != s[j]:
	               break
	           else:
	               j = j+1
	               if j - i == len(p):
	                   return True
	       i = i+1
	   return False

ls = ["a", "<", "s", "r", "i","p", "t", "/", ">"]
#ls = ['r', 'e', 'd', ' ', 'b', 'l', 'u', 'e', ' ', 't', 'h', 'r', 'e', 'e', ' ', 'h', 't', 't', 'p', ':', '/', '/', 'v', 'i', 'c', 't', 'i', 'm', '.', 'c', 'o', 'm', '/', 'p', 'o', 's', 't', '.', 'p', 'h', 'p', '?', 's', '=', '<', 's', 'c', 'r', 'i', 'p', 't', '>', 'd', 'o', 'c', 'u', 'm', 'e', 'n', 't', '.', 'l', 'o', 'c', 'a', 't', 'i', 'o', 'n', '=', "'", 't', 'r', 'u', 'd', 'y', 's', 'e', 'r', 'v', 'e', 'r', '.', 'c', 'o', 'm', '/', 'b', 'a', 'd', '.', 'p', 'h', 'p', '?', "'", ' ', '+', ' ', 'd', 'o', 'c', 'u', 'm', 'e', 'n', 't', '.', 'c', 'o', 'o', 'k', 'i', 'e', '<', '/', 's', 'c', 'i', 'p', 't', '>']

res = issubstring(ls, SCRIPT_PAT)

print(res)

