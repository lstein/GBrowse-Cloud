function load(){
	// This instantiates the dragging functionality for the attached and unattached snapshots
	// Upon receiving a new snapshot, each container executes the appropriate attach command
	$(".sortable.unattached").sortable({
		connectWith: ".sortable",
		tolerance: "pointer",
		revert: true,
		opacity: 0.8,
		container: "#attach_container",
		receive: function(event, ui){
			ui.item.css('background-color', '#E2EBFE');
			var selected = ui.item.attr("id");
			$('#attach_info_' + selected).hide();
			var type = 'attached';
			attach(selected, type);

		}
	});

	$(".sortable.attached").sortable({
		connectWith: ".sortable",
		tolerance: "pointer",
		revert: true,
		opacity: 0.8,
		container: "#attach_container",
		receive: function(event, ui){
			ui.item.css('background-color', '#eeee33');
			var selected = ui.item.attr("id");
			$('#attach_info_' + selected).show();
			var type = 'unattached';
			attach(selected, type);
		}
	});
	
	// The drop down has to be updated to reflect the number of slaves
	var select = $( "#numOfSlaves" );
	var number = select.attr('name');
	$('option[value=' + number + ']').attr('selected', 'selected');

	// Setup the slider interface for the number of slaves	
	var update = $( "#updateNumOfSlaves" );
	var slider = $( "<div id='slider'></div>" ).insertAfter( update ).slider({
		min: 0,
		max: 15,
		range: "min",
		animate: true,
		value: $( "#numOfSlaves" ).val(),
		slide: function( event, ui ) {
			select[ 0 ].selectedIndex = ui.value;
		}
	});
	$( "#numOfSlaves" ).change(function() {
		slider.slider( "value", this.selectedIndex );
	});
	
	var url = document.location.href;
	// finds a code if one is passed in
	var code = url.substring(url.indexOf('=')+1, url.length);

	if(code != url){
	        $.ajax({
        	        type: "POST",
               	 	url: "restart_server.pl",
	                data: "pass=" + code
        	});
	}

       	// Setup the functions which check for changes in slaves and the volumes
	setInterval("checkSlaves()", 20*1000);
	setInterval("checkVolumes()", 20*1000);
}

function attach(selected, type){
	// The keys are hidden in the webpage and the secret key has to be encoded
	var access_key = $('#access_key').html();
	var secret_key = $('#secret_key').html();
	var endpoint = $('#endpoint').html();
	var instance_id = $('#instance_id').html();
	var info = "selected=" + selected + "&type=" + type + "&access_key=" + access_key + 
			"&secret_key=" + encodeURIComponent(secret_key) + "&endpoint=" + endpoint + "&instance_id=" + instance_id;

	// An asynchronous request is made to attach or unattach the selected snapshot
	$.ajax({
		type: "POST",
		url: "attach.pl",
		data: info
	});
}

function slaves(){
	var newnumber = $('select option:selected').val();
	var oldnumber = $( "#numOfSlaves" ).attr('name');
	// We check to make sure theres a change in the number of slaves
	var type = (newnumber > oldnumber) ? 'add' : 'remove';
	var change = Math.abs(newnumber - oldnumber);

	if (change){
		if (type == 'add'){
			alert(change + ' slave machine(s) being added');
			// We add placeholders for the slaves being started, so the user knows something is happening
			placeholder(change);
		} else {
			alert(change + ' slave machine(s) being removed');
		}
	        var access_key = $('#access_key').html();
       		var secret_key = $('#secret_key').html();
	        var endpoint = $('#endpoint').html();
		var info = "type=" + type + "&number=" + change + "&access_key=" + access_key +
                        "&secret_key=" + encodeURIComponent(secret_key) + "&endpoint=" + endpoint;

	        $( "#numOfSlaves" ).attr('name', newnumber);  	

		//AJAX request to either add or remove backend slave machines
		$.ajax({
			type: "POST",
			url: "slaves.pl",
			data: info,
			success: function(data){
				var data = jQuery.parseJSON(data)			
				if(type == 'remove'){
					// We call a function to check the status of all slaves
					checkSlaves(data.pending);
				} else {
					// We call the function to add the information for the new slaves to the webpage
					addNew(data.instances);
				}
		                $.ajax({
	                        	type: "POST",
	        	               	 url: "restart_server.pl",
                		        data: "pass=" + data.code
        		        });
			}	
		});
	}
}

function checkSlaves(data){
	// Each slave has its status checked individually
	$(".slave_container:visible").each(function () {
		var id = this.id;
		slaveStatus(id);
	});
	
	if(data){	
		var numPlaceholders = $('.placeholder').length;
		var difference = numPlaceholders - data;
		while(difference > 0){
			var container = $('.placeholder:first');
			container.hide();
                	container.removeClass('placeholder');
                	container.addClass('deleted');
			difference--;
		}
	}
}

function checkVolumes(){
	// Each volume has its status checked individually
	$(".volume_container", ".attached").each(function () {
		var id = this.id;
		volumeStatus(id);
	});
}

function slaveStatus(instanceId){
        var access_key = $('#access_key').html();
        var secret_key = $('#secret_key').html();
        var endpoint = $('#endpoint').html();
	var info = "slave=" + instanceId + "&access_key=" + access_key +
                        "&secret_key=" + encodeURIComponent(secret_key) + "&endpoint=" + endpoint;
	$.ajax({
		type: "POST",
		url: "slaveStatus.pl",
		data:info,
		success: function(data){
			// Depending on the status of the slave, the background colors for their containers change
			var bgcolor;
			var data = jQuery.parseJSON(data)
			if (data.status == 'terminated'){
				// We hide the slave once it is terminated
				$('#' + instanceId).hide();
			} else if (data.status == 'running'){
				// change the background color and update the rest of the information for the slave
                                bgcolor = '#E2EBFE';
				update(instanceId, data);
				$('#' + instanceId).css('background-color', bgcolor);
                        } else if (data.status == 'pending'){
                                bgcolor = '#eeee33';
				$('#' + instanceId).css('background-color', bgcolor);
                        } else if (data.status == 'shutting-down') {
                                bgcolor = '#ff2233';
				$('#' + instanceId).css('background-color', bgcolor);
                        }
		}
	});
}

function volumeStatus(snapshotId){
        var access_key = $('#access_key').html();
        var secret_key = $('#secret_key').html();
        var endpoint = $('#endpoint').html();
        var info = "snapshot=" + snapshotId + "&access_key=" + access_key +
                        "&secret_key=" + encodeURIComponent(secret_key) + "&endpoint=" + endpoint;
        $.ajax({
                type: "POST",
                url: "volumeStatus.pl",
                data:info,
                success: function(data){
                        var bgcolor;
                        var data = jQuery.parseJSON(data);
			// We update the color of the container depending on its status
                        if (data.status == 'attached' || data.status == 'busy'){
                                bgcolor = '#E2EBFE';
                                $('#' + snapshotId).css('background-color', bgcolor);
				$('#attach_info_' + snapshotId).hide();
                        } else if (data.status == 'attaching') {
                                bgcolor = '#eeee33';
                                $('#' + snapshotId).css('background-color', bgcolor);
				$('#attach_info_' + snapshotId).show();
                        } else if (data.status == 'detaching') {
				bgcolor = '#ff2233';
				$('#' + snapshotId).css('background-color', bgcolor);
			} 
                }
        });

}

function placeholder(number){
	// We add a generic placeholder div for each slave being created, this relies on all new slaves being created properly
	var html = '<div class="placeholder" id="" style="background-color:#eeee33; border:1px solid #BCB79E;">';
        html += '<table width=100%><tr><td width=50%>Instance ID:</td><td width=50%>IP Address:</td></tr>';
 	html += '<tr><td width=50%>Public DNS:</td><td width=50%>Private DNS:</td></tr></table></div>  ';

	for(var i = 0; i < number; i++){
		$('#slave_list').append(html);
	}
}

function addNew(data){
	// Once a slave is created, we change a placeholder to be an actual container for that slave
	instances = data.split("&");
	instances = jQuery.makeArray(instances);
	for (var i = 0; i<instances.length; i++){
		var container = $('.placeholder:first')
		container.attr('id',instances[i]);
		container.removeClass('placeholder');
		container.addClass('slave_container');
	}
	checkSlaves();
}

function update(instanceId, data){
	// We update the information in the slave container
	$('#' + instanceId + ' td:eq(0)').html('Instance ID: ' + instanceId);
        $('#' + instanceId + ' td:eq(1)').html('IP Address: ' + data.private_ip);
	$('#' + instanceId + ' td:eq(2)').html('Public DNS: ' + data.public_dns);
	$('#' + instanceId + ' td:eq(3)').html('Private DNS: ' + data.private_dns);
}
