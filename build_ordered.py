import sys, os, re, subprocess

def read_deps() -> dict:
	r = {}
	with os.scandir(".") as it:
		for e in it:
			if not e.is_file() or not os.access(e.path, os.X_OK):
				continue
			tmp = set()
			with open(e.path, "r") as f:
				for line in f:
					m = re.search(r"\$\(\s*depend_get_path\s+([\w-]+)\s*\)", line)
					if m:
						tmp.add(m.group(1))
			r[e.name] = sorted(list(tmp))
	return r

def build_order(deps: dict, want: list) -> list:
	# simply walk every dependency in order, without duplicates
	# (this won't detect loops)
	r = []
	def recurse(t):
		for t2 in deps[t]:
			assert t2 != t
			recurse(t2)
		if t not in r:
			r.append(t)
	for t in want:
		recurse(t)
	assert len(set(r)) == len(r)
	return r

def run_build(args: list, targets: list):
	for t in targets:
		subprocess.check_call(["./%s" % t] + args, stdin=subprocess.DEVNULL)

if __name__ == "__main__":
	args = []
	targets = []
	tmp = False
	for arg in sys.argv[1:]:
		if arg in ("-h", "--help"):
			print("Usage: build_ordered.py [...] -- <target> [target...]")
			print("Builds specified targets including dependencies. Flags are passed through.")
			exit(0)
		elif arg == "--":
			tmp = True
		else:
			(targets if tmp else args).append(arg)
	if not tmp:
		raise ValueError("Missing -- in arguments")
	targets = list(set(targets))
	if not targets:
		raise ValueError("No targets specified")
	deps = read_deps()
	for t in targets:
		if t not in deps.keys():
			raise ValueError("Target not found: %s" % t)
	order = build_order(deps, targets)
	print("Build order:", ", ".join(order), file=sys.stderr)
	run_build(args, order)
	exit(0)
