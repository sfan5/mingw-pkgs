import sys, os, re, subprocess

def read_deps() -> dict:
	r = {}
	with os.scandir(".") as it:
		for e in it:
			# the build scripts are executable scripts with a "bare" name
			if not e.is_file() or "." in e.name or not os.access(e.path, os.X_OK):
				continue
			mydeps = set()
			with open(e.path, "r") as f:
				for line in f:
					if re.match(r"^\s*#", line):
						continue
					m = re.search(r"\$\(\s*depend_get_path\s+([^\)]+)\)", line)
					if not m:
						continue
					tmp = m.group(1).strip()
					if re.match(r"\w[\w-]*", tmp):
						mydeps.add(tmp)
					else:
						print("Warning: Can't determine dependency in %s from line: %s" %
							(e.name, line.strip()), file=sys.stderr)
			r[e.name] = sorted(list(mydeps))
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
	try:
		run_build(args, order)
	except KeyboardInterrupt:
			exit(1)
	exit(0)
