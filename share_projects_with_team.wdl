version 1.0

# This workflow is identical to share_project_with_team except it takes
# an array of project URIs instead of just one. It will use some common
# sense timers to (hopefully) prevent overloading the API. Intentionally,
# it prints every successful share so you can skip them if you need to
# attempt a retry.
#
# Waits (excluding retries):
# * 1 second per API call
# * 20 seconds per batch of 20 API calls
# * 360 seconds (5 min) per superbatch of 20 batches (ie, 400 API calls)
#
# I have hardcoded WDL retries to 0 and turned off preemptibles, 
# because if the WDL fails after you've already shared at least one
# project, it will start from the very beginning and attempt to share
# that which is already shared.

workflow Microreact_Share_Team_MULTIPLE {
	input {
		File token
		String team_uri
		Array[String] project_uris
		Boolean grant_editor_role  = false
		Boolean grant_manager_role = false
		Int max_python_retries     = 1
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

	call mr_share_MULTIPLE_with_team {
		input:
			token = token,
			team_uri = team_uri,
			project_uris = project_uris,
			role = role,
			max_python_retries = max_python_retries
	}

	output {
		# We need this empty bogus output to call this workflow as a subworkflow by Tree Nine
	}

}

task mr_share_MULTIPLE_with_team {
	input {
		File token
		String team_uri
		Array[String] project_uris
		String role     # must be "viewer", "editor", or "manager"
		Int max_python_retries
	}
	
	command <<<
		set -eu pipefail
		set +x
		# unbuffered, so we have some idea of its progress
		python3 -u << CODE
		import requests
		import time
		import json

		with open("~{token}", 'r', encoding="utf-8") as file:
			TOKEN_STR = file.readline().strip()

		def wait(retries):
			if ~{max_python_retries} - retries == 1:
				print("WAITING ONE MINUTE, THEN RETRYING...")
				time.sleep(60)
			elif ~{max_python_retries} - retries <= 0:
				return
			else:
				print("WAITING TWO SECONDS, THEN RETRYING...")
				time.sleep(2)

		project_uris = "~{sep=',' project_uris}".split(",")
		
		def add_mr_project_to_team(token, this_payload, retries=-1):
			if retries < ~{max_python_retries}:
				try:
					response = requests.post("https://microreact.org/api/shares/add-team",
						headers={"Access-Token": token, "Content-Type": "application/json; charset=UTF-8"},
						timeout=20,
						data=this_payload)
					if response.status_code == 200:
						print(f"[INFO] Successfully shared {json.loads(this_payload)['project']}")
						return
					print(f"[WARNING] Failed to add project {json.loads(this_payload)['project']} to ~{team_uri} [code {response.status_code}]: {response.text}")
					retries =+ 1
					wait(retries)
					add_mr_project_to_team(token, this_payload, retries)
				except Exception as e: # ignore: broad-exception-caught
					print(f"[WARNING] Caught exception trying to add project {json.loads(this_payload)['project']} to team ~{team_uri}: {e}")
					retries =+ 1
					wait(retries)
					add_mr_project_to_team(token, this_payload, retries)
			else:
				print("[ERROR] Failed to add project {json.loads(this_payload)['project']} to team ~{team_uri} after ~{max_python_retries} retries. Something's broken.")
				exit(1)

		batch_count = 0
		call_count = 0

		for i, project_uri in enumerate(project_uris):
			payload_dict = {
				"team": "~{team_uri}",
				"project": project_uri,
				"role": "~{role}"
			}
			payload = json.dumps(payload_dict)

			add_mr_project_to_team(TOKEN_STR, payload)
			call_count += 1
			time.sleep(1)

			# After every 20 calls, wait 20 seconds
			if call_count % 20 == 0:
				batch_count += 1
				print("[INFO] Completed batch of 20. Waiting 20 seconds...")
				time.sleep(20)

				# After every 20 batches (400 calls), wait 5 minutes
				if batch_count % 20 == 0:
					print("[INFO] Completed 20 batches (400 calls). Waiting 5 minutes...")
					time.sleep(300)

		CODE

	>>>

	runtime {
		cpu: 2
		disks: "local-disk 10 HDD"
		docker: "ashedpotatoes/dropkick:0.0.2"
		memory: "8 GB"
		maxRetries: 0
	}
}
