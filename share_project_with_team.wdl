version 1.0

workflow Microreact_Share_Project_With_Team {
	input {
		File token
		String team_uri
		String project_uri
		Boolean grant_editor_role  = false
		Boolean grant_manager_role = false
		Boolean verbose            = true
		Int max_python_retries     = 1
		Int max_wdl_retries        = 0
	}

	# WDL doesn't have a sense of mutual exclusivity so this will be a little silly
	# effectively: 
	# if manager + editor --> manager
	# if manager + !editor --> manager
	# if !manager + editor --> editor
	# if !manager + !editor --> viewer
	if (grant_manager_role) {
		String manager = "manager"
	}
	if (grant_editor_role) {
		String editor = "editor"
	}
	String role = select_first([manager, editor, "viewer"])

	call mr_share_with_team {
		input:
			token = token,
			team_uri = team_uri,
			project_uri = project_uri,
			role = role,
			verbose = verbose,
			max_python_retries = max_python_retries,
			max_wdl_retries = max_wdl_retries
	}

}

task mr_share_with_team {
	input {
		File token
		String team_uri
		String project_uri
		String role     # must be "viewer", "editor", or "manager"
		Boolean verbose
		Int max_python_retries
		Int max_wdl_retries
	}
	
	command <<<
		set -eu pipefail
		set +x
		python3 << CODE
		import requests
		import time
		import json

		# https://github.com/openwdl/wdl/blob/legacy/versions/1.0/SPEC.md#true-and-false
		verbose = bool(~{true='True' false='False' verbose})
		assert type(verbose) == bool

		with open("~{token}", 'r', encoding="utf-8") as file:
			TOKEN_STR = file.readline().strip()

		def debug_print(response):
			print(f"[DEBUG] Status code: {response.status_code}")
			print(f"[DEBUG] Response body: {response.text!r}")
			print(f"[DEBUG] Response headers: {dict(response.headers)}")
			return

		def wait(retries):
			if ~{max_python_retries} - retries == 1:
				print("WAITING ONE MINUTE, THEN RETRYING...")
				time.sleep(60)
			elif ~{max_python_retries} - retries <= 0:
				return
			else:
				print("WAITING TWO SECONDS, THEN RETRYING...")
				time.sleep(2)

		payload_dict = {
			"team": "~{team_uri}",
			"project": "~{project_uri}",
			"role": "~{role}"
		}
		payload = json.dumps(payload_dict)
		if verbose: print(payload)
		
		def add_mr_project_to_team(token, payload, retries=-1):
			if retries < ~{max_python_retries}:
				try:
					response = requests.post("https://microreact.org/api/shares/add-team",
						headers={"Access-Token": token, "Content-Type": "application/json; charset=UTF-8"},
						timeout=120,
						data=payload)
					if verbose:
						debug_print(response)
					if response.status_code == 200:
						users = response.json()
						return users
					print(f"Failed to add project ~{project_uri} to ~{team_uri} [code {response.status_code}]: {response.text}")
					retries =+ 1
					wait(retries)
					add_mr_project_to_team(token, payload, retries)
				except Exception as e: # ignore: broad-exception-caught
					print(f"Caught exception trying to add project ~{project_uri} to team ~{team_uri}: {e}")
					retries =+ 1
					wait(retries)
					add_mr_project_to_team(token, payload, retries)
			else:
				print(f"Failed to add project ~{project_uri} to team ~{team_uri} after ~{max_python_retries} retries. Something's broken.")
				exit(1)

		add_mr_project_to_team(TOKEN_STR, payload)

		CODE

	>>>

	runtime {
		cpu: 2
		disks: "local-disk 10 HDD"
		docker: "ashedpotatoes/dropkick:0.0.2"
		memory: "8 GB"
		preemptible: 2
		maxRetries: max_wdl_retries
	}
}
