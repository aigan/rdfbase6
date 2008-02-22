
var RBInputPopup = Class.create(
{
    // button: id of calling element
    // result_container: where to add the result to ('ul')
    // search_crit:      passed to $R->find; already as json
    // search_type:      what is inputted ('name_clean_like')
    // pred_name:        ???
    // subj:             ???
    // rev:              ???
    initialize: function(button, divid, search_crit,
			 search_type, pred_name, subj, rev)
    {
	this.divid = divid;
	this.search_crit = \$H(search_crit.evalJSON());
	this.search_type = search_type;
	this.button = \$(button);
	this.pred_name = pred_name;
	this.subj = subj;
	this.rev = rev;

	this.loading = Builder.node('img', {
		id: 'rb_input_loading',
		style: 'display: none; position: absolute; top: 45%; left: 45%; z-index: 10',
		src: '[%home%]/img/loading_large.gif'
	    }, '');
	\$(this.divid).appendChild(this.loading);
	this.button.onclick = this.openPopup.bind(this);
    },

    openPopup: function()
    {
	this.popup = document.createElement('div');
	this.popup.id = 'rb_input_popup';
	this.popup.style.border = '1px solid black';
	this.popup.style.display= 'none';
	this.popup.style.position = 'absolute';
	this.popup.style.padding = '.5em';
	this.popup.style.backgroundColor = 'yellow';
	this.popup.style.zIndex = '5';
	new Draggable(this.popup);

	this.form = document.createElement('form');
	this.form.id = 'rb_input_form';
	this.form.onsubmit = this.lookup.bindAsEventListener(this);
	this.popup.appendChild(this.form);

	this.input = document.createElement('input');
	this.input.id = 'rb_input';
	this.form.appendChild(this.input);

	this.submit = document.createElement('input');
	this.submit.id = 'rb_input_button';
	this.submit.value = '[% loc('Lookup') %]';
	this.submit.type = 'submit';
	this.form.appendChild(this.submit);

	this.cancel = document.createElement('input');
	this.cancel.type = 'button';
	this.cancel.value = '[% loc('Cancel') %]';
	this.cancel.onclick = this.close.bind(this);
	this.form.appendChild(this.cancel);
	
	this.button.insert({ after: this.popup });
	Effect.Appear(this.popup, { duration: 0.5 });
	setTimeout(function() {this.input.activate();}.bind(this), 500);
    },

    close: function()
    {
	Effect.Fade(this.popup, { duration: 0.5 });
	delete( this );
    },

    lookup: function(event)
    {
	event.stop();

	var value = \$('rb_input').getValue();

	var search = this.search_crit.merge({});
	search._object[this.search_type] =  value;

	Effect.Appear(this.loading, { duration: 0.5 });
	new Ajax.Request('[%home%]/ajax/lookup', {
		method: 'get',
		    parameters: { params: Object.toJSON(search) },
		    requestHeaders: { Accept: 'application/json' },
		    onComplete: function(transport)
		    {
			Effect.Fade(this.loading, { duration: 0.5 });
			var result = transport.responseText.evalJSON();
			this.show_result(result);
		    }.bind(this)
			  });

	return false;
    },

    show_result: function(result)
    {
	var old_list = this.popup_li;

	this.popup_li = document.createElement('ul');
	this.popup_li.style.display = 'none';
	this.popup_li.style.listStyleType = 'none';
	this.popup_li.style.margin = '0';
	this.popup_li.style.padding = '0';
	this.popup_li.style.whiteSpace = 'nowrap';
	this.popup.appendChild(this.popup_li);
	this.result = \$A(result);

	if( \$H(result[0]).get('id') == 0 ) {
	    var line = Builder.node('li', \$H(result[0]).get('name'));
	    this.popup_li.appendChild(line);
	}
	else {
	    this.result.each( function(item) {
		    var node = \$H(item);
		    var name = node.get('name');
		    var select_button = Builder.node('input', { value: 'Select', type: 'button' });
		    select_button.onclick = this.select.bindAsEventListener(this, name, node.get('id'));
		    
		    var tip_text = Builder.node('table');
		    node.each( function(npair) {
			    if( npair.key != 'form_url' ) {
				var tip_line = Builder.node('tr',
							    [ Builder.node('td', npair.key +':'),
							      Builder.node('td', npair.value) ]);
				tip_text.appendChild(tip_line);
			    }
			});
		    
		    var more_info = Builder.node('a',{ href: node.get('form_url'),
						       target: '_new',
						       onmouseover: 'Tip(\'<table>'+ tip_text.innerHTML +'</table>\', DURATION, 0, FOLLOWMOUSE, true, STICKY, false, FONTSIZE, \'12px\')'
			                             },
			                         name);
		
		    var line = Builder.node('li', [ select_button, ' ', more_info ] );
		    this.popup_li.appendChild(line);
		}.bind(this));
	}

	var value = \$('rb_input').getValue();
	var create_new_button = Builder.node('input', { value: 'Create a new "'+ value +'"',
							type: 'button' });
	create_new_button.onclick = this.createNew.bindAsEventListener(this, value);
	var line = Builder.node('li', create_new_button);
	this.popup_li.appendChild(line);

	if( old_list ) {
	    Effect.BlindUp(old_list, { duration: 0.5 });
	    Effect.BlindDown(this.popup_li, { delay: 0.4, duration: 0.5 });
	}
	else {
	    Effect.BlindDown(this.popup_li, { duration: 0.5 });
	}
    },

    select: function(event, name, key)
    {
	pps[this.divid].loadingStart();
	new Ajax.Request('[%home%]/ajax/action/add_direct', {
		method: 'get',
		parameters: {
		    subj: this.subj,
			pred_name: this.pred_name,
			obj: key,
			rev: this.rev
			
		},
		onComplete: function(transport)
		{
		    pps[this.divid].update();
		}.bind(this)
	    });
    },

    addToList: function(result)
    {
	Effect.Fade(this.popup, { duration: 0.5 });
	var line = document.createElement(this.result_type);
	line.style.display = 'none';
	line.innerHTML = result;
	this.result_container.appendChild(line);
	Effect.BlindDown(line, { delay: 0.4 });
    },

    createNew: function(event, value)
    {
	Effect.Appear(this.loading, { duration: 0.5 });

	new Ajax.Request('[%home%]/ajax/action/create_new', {
		method: 'get',
		parameters: {
		    name: value,
			params: Object.toJSON(this.search_crit),
			subj: this.subj,
			pred_name: this.pred_name
		},
		onComplete: function(transport)
		{
		    Effect.Fade(this.loading, { duration: 0.5 });
		    pps[this.divid].update();
		    this.close();
		}.bind(this)
	    });
	
    }
});


function rb_remove_arc(divid, arc)
{
    if( confirm('Really remove arc?') ) {
	loading = Builder.node('img', {
		id: 'rb_input_loading',
		style: 'display: none; position: absolute; top: 45%; left: 45%;',
		src: '[%home%]/img/loading_large.gif'
	    }, '');
	\$(divid).appendChild(loading);
	pps[divid].loadingStart();
	
	new Ajax.Request('[%home%]/ajax/action/remove_arc', {
		method: 'get',
		    parameters: { arc: arc },
		    onComplete: function(transport)
		    {
			pps[divid].update();
		    }
	});
    }
}


var pps = new Hash();
var pps_deps = new Hash();

var PagePart = Class.create(
{
    initialize: function(element, update_url, params)
    {
	this.element = \$(element);
	this.update_url = update_url;
	this.update_params = params['params'];
	this.is_loading = false;

	if( params['depends_on'] ) {
	    this.depends_on = params['depends_on'];

	    params['depends_on'].each(function(depo) {
		    if( !pps_deps[depo] ) {
			pps_deps[depo] = new Array();
		    }
		    pps_deps[depo].push(this);
		}.bind(this));
	}
	if( params['update_button'] ) {
	    this.registerUpdateButton(\$(params['update_button']));
	}

	this.loadingSetup();

	pps[element] = this;
    },

    registerUpdateButton: function(button)
    {
	this.update_button = \$(button);
	Event.observe(this.update_button, 'click', this.update.bind(this));
    },

    loadingSetup: function()
    {
	this.loading = Builder.node('img', {
		id: 'rb_input_loading',
		style: 'display: none; position: absolute; top: 45%; left: 45%;',
		src: '[%home%]/img/loading_large.gif'
	    }, '');
	this.element.appendChild(this.loading);
    },

    loadingStart: function()
    {
	if( this.is_loading == false ) {
	    //Effect.Fold(this.element, { duration: 0.5 });
	    Effect.Appear(this.loading, { duration: 0.5 });
	    this.is_loading = true;
	}
    },

    loadingEnd: function()
    {
	if( this.is_loading ) {
	    Effect.Fade(this.loading, { duration: 0.5 });
	    //Effect.Unfold(this.element, { duration: 0.5 });
	    this.is_loading = false;
	}
    },

    update: function()
    {
	this.loadingStart();
	this.update_params['divid'] = this.element.id;
	new Ajax.Updater(this.element, this.update_url, {
		method: 'get',
		parameters: { params: Object.toJSON(this.update_params) },
		evalScripts: true,
		onComplete: function(transport)
		{
		    this.updateOthers();
		    this.loadingEnd();
		}.bind(this)
	    });
    },

    updateOthers: function()
    {
	if( pps_deps[this.element.id] ) {
	    pps_deps[this.element.id].each(function(pp) {
		    pp.update();
		});
	}
    },

    performAction: function( action, extra_params )
    {
	var form;
	if( extra_params.form ) {
	    form = \$( extra_params.form );
	}
	else {
	    form = \$( 'f' );
	}

	if( extra_params.confirm ) {
	    if( !confirm( extra_params.confirm ) ) {
		return(false);
	    }
	}

	this.loadingStart();
	var formData = \$H(form.serialize(true)).merge({ run: action });
	formData = formData.merge(extra_params);

	new Ajax.Updater( this.element, '[%home%]/clean/update_button_answer.tt', {
		method: 'post',
		    parameters: formData.toQueryString(),
		    onComplete: function(transport)
		    {
			this.updateOthers();
			this.loadingEnd();
		    }.bind(this)
			  });
    },
    
    insert_wu: function( after, args_json )
    {
	this.loadingStart();
	new Ajax.Request('[%home%]/ajax/wu', {
		method: 'get',
		    parameters: { params: args_json },
		    onComplete: function(transport)
		    {
			this.loadingEnd();
			\$(after).insert({ after: transport.responseText });
			new_part = \$(after).next();
			prepareForm();
			Effect.Grow(new_part, { delay: 0.5, duration: 0.5 });
		    }.bind(this)
			  });
    }
    

});
